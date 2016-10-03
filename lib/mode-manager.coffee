_ = require 'underscore-plus'
{Emitter, Range, CompositeDisposable, Disposable} = require 'atom'
Base = require './base'
swrap = require './selection-wrapper'
{moveCursorLeft} = require './utils'
settings = require './settings'

class ModeManager
  mode: 'insert' # Native atom is not modal editor and its default is 'insert'
  submode: null
  replacedCharsBySelection: null

  constructor: (@vimState) ->
    {@editor, @editorElement} = @vimState
    @mode = 'insert'
    @emitter = new Emitter
    @subscriptions = new CompositeDisposable
    @subscriptions.add @vimState.onDidDestroy(@destroy.bind(this))

  destroy: ->
    @subscriptions.dispose()

  isMode: (mode, submodes) ->
    if submodes?
      (@mode is mode) and (@submode in [].concat(submodes))
    else
      @mode is mode

  # Event
  # -------------------------
  onWillActivateMode: (fn) -> @emitter.on('will-activate-mode', fn)
  onDidActivateMode: (fn) -> @emitter.on('did-activate-mode', fn)
  onWillDeactivateMode: (fn) -> @emitter.on('will-deactivate-mode', fn)
  preemptWillDeactivateMode: (fn) -> @emitter.preempt('will-deactivate-mode', fn)
  onDidDeactivateMode: (fn) -> @emitter.on('did-deactivate-mode', fn)

  # activate: Public
  #  Use this method to change mode, DONT use other direct method.
  # -------------------------
  activate: (mode, submode=null) ->
    # Avoid odd state(=visual-mode but selection is empty)
    return if (mode is 'visual') and @editor.isEmpty()

    @emitter.emit('will-activate-mode', {mode, submode})

    if (mode is 'visual') and (submode is @submode)
      [mode, submode] = ['normal', null]

    @deactivate() if (mode isnt @mode)

    @deactivator = switch mode
      when 'normal' then @activateNormalMode()
      when 'operator-pending' then @activateOperatorPendingMode()
      when 'insert' then @activateInsertMode(submode)
      when 'visual' then @activateVisualMode(submode)

    @editorElement.classList.remove("#{@mode}-mode")
    @editorElement.classList.remove(@submode)

    [@mode, @submode] = [mode, submode]

    @editorElement.classList.add("#{@mode}-mode")
    @editorElement.classList.add(@submode) if @submode?

    if @mode is 'visual'
      @updateNarrowedState()
      @vimState.updatePreviousSelection()

    @vimState.statusBarManager.update(@mode, @submode)
    @vimState.updateCursorsVisibility()

    @emitter.emit('did-activate-mode', {@mode, @submode})

  deactivate: ->
    unless @deactivator?.disposed
      @emitter.emit('will-deactivate-mode', {@mode, @submode})
      @deactivator?.dispose()
      @emitter.emit('did-deactivate-mode', {@mode, @submode})

  # Normal
  # -------------------------
  activateNormalMode: ->
    @vimState.reset()
    # [FIXME] Component is not necessary avaiable see #98.
    @editorElement.component?.setInputEnabled(false)
    new Disposable

  # Operator Pending
  # -------------------------
  activateOperatorPendingMode: ->
    new Disposable

  # Insert
  # -------------------------
  activateInsertMode: (submode=null) ->
    @editorElement.component.setInputEnabled(true)
    replaceModeDeactivator = @activateReplaceMode() if submode is 'replace'

    new Disposable =>
      replaceModeDeactivator?.dispose()
      replaceModeDeactivator = null

      if settings.get('clearMultipleCursorsOnEscapeInsertMode')
        @editor.clearSelections()

      # When escape from insert-mode, cursor move Left.
      needSpecialCareToPreventWrapLine = atom.config.get('editor.atomicSoftTabs') ? true
      for cursor in @editor.getCursors()
        moveCursorLeft(cursor, {needSpecialCareToPreventWrapLine})

  activateReplaceMode: ->
    @replacedCharsBySelection = {}
    subs = new CompositeDisposable
    subs.add @editor.onWillInsertText ({text, cancel}) =>
      cancel()
      @editor.getSelections().forEach (selection) =>
        for char in text.split('') ? []
          if (char isnt "\n") and (not selection.cursor.isAtEndOfLine())
            selection.selectRight()
          @replacedCharsBySelection[selection.id] ?= []
          @replacedCharsBySelection[selection.id].push(swrap(selection).replace(char))

    subs.add new Disposable =>
      @replacedCharsBySelection = null
    subs

  getReplacedCharForSelection: (selection) ->
    @replacedCharsBySelection[selection.id]?.pop()

  # Visual
  # -------------------------
  # At this point @submode is not yet updated to final submode.
  activateVisualMode: (submode) ->
    if @submode?
      @selectCharacterwise()
    else if @editor.getLastSelection().isEmpty()
      for selection in @editor.getSelections()
        swrap(selection).translateSelectionEndAndClip('forward')

    swrap.updateSelectionProperties(@editor, unknownOnly: true)

    switch submode
      when 'linewise'
        @vimState.selectLinewise()
      when 'blockwise'
        @vimState.selectBlockwise() unless swrap(@editor.getLastSelection()).isLinewise()

    new Disposable =>
      @normalizeSelections()
      selection.clear(autoscroll: false) for selection in @editor.getSelections()
      @updateNarrowedState(false)

  selectCharacterwise: ->
    switch @submode
      when 'linewise'
        for selection in @editor.getSelections() when not selection.isEmpty()
          swrap(selection).normalize()
          swrap(selection).translateSelectionEndAndClip('forward')
      when 'blockwise'
        for bs in @vimState.getBlockwiseSelections()
          bs.restoreCharacterwise()
        @vimState.clearBlockwiseSelections()

  normalizeSelections: ->
    @selectCharacterwise()
    swrap.clearProperties(@editor)

    # We selectRight()ed in visual-mode, so reset this effect here.
    for selection in @editor.getSelections() when swrap(selection).isForwarding()
      swrap(selection).translateSelectionEndAndClip('backward')

  # Narrow to selection
  # -------------------------
  hasMultiLineSelection: ->
    if @isMode('visual', 'blockwise')
      # [FIXME] why I need null guard here
      not @vimState.getLastBlockwiseSelection()?.isSingleRow()
    else
      not swrap(@editor.getLastSelection()).isSingleRow()

  updateNarrowedState: (value=null) ->
    @editorElement.classList.toggle('is-narrowed', value ? @hasMultiLineSelection())

  isNarrowed: ->
    @editorElement.classList.contains('is-narrowed')

module.exports = ModeManager
