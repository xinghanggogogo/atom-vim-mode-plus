_ = require 'underscore-plus'
{Emitter, CompositeDisposable} = require 'atom'

module.exports =
class RangeMakerManager
  patterns: null

  constructor: (@vimState) ->
    {@editor, @editorElement} = @vimState
    @disposables = new CompositeDisposable
    @disposables.add @vimState.onDidDestroy(@destroy.bind(this))
    @emitter = new Emitter

    @markerLayer = @editor.addMarkerLayer()
    options = {type: 'highlight', class: 'vim-mode-plus-range-marker'}
    @decorationLayer = @editor.decorateMarkerLayer(@markerLayer, options)

    # Update css on every marker update.
    @markerLayer.onDidUpdate =>
      @editorElement.classList.toggle("with-range-marker", @hasMarkers())

  destroy: ->
    @decorationLayer.destroy()
    @disposables.dispose()
    @markerLayer.destroy()

  # Markers
  # -------------------------
  markBufferRange: (range) ->
    @markerLayer.markBufferRange(range)

  hasMarkers: ->
    @markerLayer.getMarkerCount() > 0

  getMarkers: ->
    @markerLayer.getMarkers()

  clearMarkers: ->
    marker.destroy() for marker in @markerLayer.getMarkers()

  getMarkerBufferRanges: ->
    @markerLayer.getMarkers().map (marker) ->
      marker.getBufferRange()

  getMarkerAtPoint: (point) ->
    @markerLayer.findMarkers(containsBufferPosition: point)[0]
