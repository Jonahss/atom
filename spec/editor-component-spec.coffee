_ = require 'underscore-plus'
{extend, flatten, toArray, last} = _

ReactEditorView = require '../src/react-editor-view'
nbsp = String.fromCharCode(160)

describe "EditorComponent", ->
  [contentNode, editor, wrapperView, component, node, verticalScrollbarNode, horizontalScrollbarNode] = []
  [lineHeightInPixels, charWidth, delayAnimationFrames, nextAnimationFrame, lineOverdrawMargin] = []

  beforeEach ->
    lineOverdrawMargin = 2

    waitsForPromise ->
      atom.packages.activatePackage('language-javascript')

    runs ->
      spyOn(window, "setInterval").andCallFake window.fakeSetInterval
      spyOn(window, "clearInterval").andCallFake window.fakeClearInterval

      delayAnimationFrames = false
      nextAnimationFrame = null
      spyOn(window, 'requestAnimationFrame').andCallFake (fn) ->
        if delayAnimationFrames
          nextAnimationFrame = fn
        else
          fn()

    waitsForPromise ->
      atom.project.open('sample.js').then (o) -> editor = o

    runs ->
      contentNode = document.querySelector('#jasmine-content')
      contentNode.style.width = '1000px'

      wrapperView = new ReactEditorView(editor, {lineOverdrawMargin})
      wrapperView.attachToDom()
      {component} = wrapperView
      component.setLineHeight(1.3)
      component.setFontSize(20)

      lineHeightInPixels = editor.getLineHeightInPixels()
      charWidth = editor.getDefaultCharWidth()
      node = component.getDOMNode()
      verticalScrollbarNode = node.querySelector('.vertical-scrollbar')
      horizontalScrollbarNode = node.querySelector('.horizontal-scrollbar')

      node.style.height = editor.getLineCount() * lineHeightInPixels + 'px'
      node.style.width = '1000px'
      component.measureScrollView()

  afterEach ->
    contentNode.style.width = ''

  describe "line rendering", ->
    it "renders the currently-visible lines plus the overdraw margin", ->
      node.style.height = 4.5 * lineHeightInPixels + 'px'
      component.measureScrollView()

      linesNode = node.querySelector('.lines')
      expect(linesNode.style['-webkit-transform']).toBe "translate3d(0px, 0px, 0px)"
      expect(node.querySelectorAll('.line').length).toBe 6 + 2 # no margin above
      expect(component.lineNodeForScreenRow(0).textContent).toBe editor.lineForScreenRow(0).text
      expect(component.lineNodeForScreenRow(0).offsetTop).toBe 0
      expect(component.lineNodeForScreenRow(5).textContent).toBe editor.lineForScreenRow(5).text
      expect(component.lineNodeForScreenRow(5).offsetTop).toBe 5 * lineHeightInPixels

      verticalScrollbarNode.scrollTop = 4.5 * lineHeightInPixels
      verticalScrollbarNode.dispatchEvent(new UIEvent('scroll'))

      expect(linesNode.style['-webkit-transform']).toBe "translate3d(0px, #{-4.5 * lineHeightInPixels}px, 0px)"
      expect(node.querySelectorAll('.line').length).toBe 6 + 4 # margin above and below
      expect(component.lineNodeForScreenRow(2).offsetTop).toBe 2 * lineHeightInPixels
      expect(component.lineNodeForScreenRow(2).textContent).toBe editor.lineForScreenRow(2).text
      expect(component.lineNodeForScreenRow(9).offsetTop).toBe 9 * lineHeightInPixels
      expect(component.lineNodeForScreenRow(9).textContent).toBe editor.lineForScreenRow(9).text

    it "updates the top position of subsequent lines when lines are inserted or removed", ->
      editor.getBuffer().deleteRows(0, 1)
      lineNodes = node.querySelectorAll('.line')
      expect(component.lineNodeForScreenRow(0).offsetTop).toBe 0
      expect(component.lineNodeForScreenRow(1).offsetTop).toBe 1 * lineHeightInPixels
      expect(component.lineNodeForScreenRow(2).offsetTop).toBe 2 * lineHeightInPixels

      editor.getBuffer().insert([0, 0], '\n\n')
      lineNodes = node.querySelectorAll('.line')
      expect(component.lineNodeForScreenRow(0).offsetTop).toBe 0 * lineHeightInPixels
      expect(component.lineNodeForScreenRow(1).offsetTop).toBe 1 * lineHeightInPixels
      expect(component.lineNodeForScreenRow(2).offsetTop).toBe 2 * lineHeightInPixels
      expect(component.lineNodeForScreenRow(3).offsetTop).toBe 3 * lineHeightInPixels
      expect(component.lineNodeForScreenRow(4).offsetTop).toBe 4 * lineHeightInPixels

    it "updates the top position of lines when the line height changes", ->
      initialLineHeightInPixels = editor.getLineHeightInPixels()
      component.setLineHeight(2)

      newLineHeightInPixels = editor.getLineHeightInPixels()
      expect(newLineHeightInPixels).not.toBe initialLineHeightInPixels
      expect(component.lineNodeForScreenRow(1).offsetTop).toBe 1 * newLineHeightInPixels

    it "updates the top position of lines when the font size changes", ->
      initialLineHeightInPixels = editor.getLineHeightInPixels()
      component.setFontSize(10)

      newLineHeightInPixels = editor.getLineHeightInPixels()
      expect(newLineHeightInPixels).not.toBe initialLineHeightInPixels
      expect(component.lineNodeForScreenRow(1).offsetTop).toBe 1 * newLineHeightInPixels

    it "updates the top position of lines when the font family changes", ->
      # Can't find a font that changes the line height, but we think one might exist
      linesComponent = component.refs.lines
      spyOn(linesComponent, 'measureLineHeightAndDefaultCharWidth').andCallFake -> editor.setLineHeightInPixels(10)

      initialLineHeightInPixels = editor.getLineHeightInPixels()
      component.setFontFamily('sans-serif')

      expect(linesComponent.measureLineHeightAndDefaultCharWidth).toHaveBeenCalled()
      newLineHeightInPixels = editor.getLineHeightInPixels()
      expect(newLineHeightInPixels).not.toBe initialLineHeightInPixels
      expect(component.lineNodeForScreenRow(1).offsetTop).toBe 1 * newLineHeightInPixels

    it "renders the .lines div at the full height of the editor if there aren't enough lines to scroll vertically", ->
      editor.setText('')
      node.style.height = '300px'
      component.measureScrollView()

      linesNode = node.querySelector('.lines')
      expect(linesNode.offsetHeight).toBe 300

    describe "when showInvisibles is enabled", ->
      invisibles = null

      beforeEach ->
        invisibles =
          eol: 'E'
          space: 'S'
          tab: 'T'
          cr: 'C'

        atom.config.set("editor.showInvisibles", true)
        atom.config.set("editor.invisibles", invisibles)

      it "re-renders the lines when the showInvisibles config option changes", ->
        editor.setText " a line with tabs\tand spaces "

        expect(component.lineNodeForScreenRow(0).textContent).toBe "#{invisibles.space}a line with tabs#{invisibles.tab} and spaces#{invisibles.space}#{invisibles.eol}"
        atom.config.set("editor.showInvisibles", false)
        expect(component.lineNodeForScreenRow(0).textContent).toBe " a line with tabs  and spaces "
        atom.config.set("editor.showInvisibles", true)
        expect(component.lineNodeForScreenRow(0).textContent).toBe "#{invisibles.space}a line with tabs#{invisibles.tab} and spaces#{invisibles.space}#{invisibles.eol}"

      it "displays spaces, tabs, and newlines as visible characters", ->
        editor.setText " a line with tabs\tand spaces "
        expect(component.lineNodeForScreenRow(0).textContent).toBe "#{invisibles.space}a line with tabs#{invisibles.tab} and spaces#{invisibles.space}#{invisibles.eol}"

      it "displays newlines as their own token outside of the other tokens' scopes", ->
        editor.setText "var"
        expect(component.lineNodeForScreenRow(0).innerHTML).toBe "<span class=\"source js\"><span class=\"storage modifier js\">var</span></span><span class=\"invisible-character\">#{invisibles.eol}</span>"

      it "displays trailing carriage returns using a visible, non-empty value", ->
        editor.setText "a line that ends with a carriage return\r\n"
        expect(component.lineNodeForScreenRow(0).textContent).toBe "a line that ends with a carriage return#{invisibles.cr}#{invisibles.eol}"

      describe "when soft wrapping is enabled", ->
        beforeEach ->
          editor.setText "a line that wraps "
          editor.setSoftWrap(true)
          node.style.width = 16 * charWidth + 'px'
          component.measureScrollView()

        it "doesn't show end of line invisibles at the end of wrapped lines", ->
          expect(component.lineNodeForScreenRow(0).textContent).toBe "a line that "
          expect(component.lineNodeForScreenRow(1).textContent).toBe "wraps#{invisibles.space}#{invisibles.eol}"

    describe "when indent guides are enabled", ->
      beforeEach ->
        component.setShowIndentGuide(true)

      it "adds an 'indent-guide' class to spans comprising the leading whitespace", ->
        line1LeafNodes = getLeafNodes(component.lineNodeForScreenRow(1))
        expect(line1LeafNodes[0].textContent).toBe '  '
        expect(line1LeafNodes[0].classList.contains('indent-guide')).toBe true
        expect(line1LeafNodes[1].classList.contains('indent-guide')).toBe false

        line2LeafNodes = getLeafNodes(component.lineNodeForScreenRow(2))
        expect(line2LeafNodes[0].textContent).toBe '  '
        expect(line2LeafNodes[0].classList.contains('indent-guide')).toBe true
        expect(line2LeafNodes[1].textContent).toBe '  '
        expect(line2LeafNodes[1].classList.contains('indent-guide')).toBe true
        expect(line2LeafNodes[2].classList.contains('indent-guide')).toBe false

      it "renders leading whitespace spans with the 'indent-guide' class for empty lines", ->
        editor.getBuffer().insert([1, Infinity], '\n')

        line2LeafNodes = getLeafNodes(component.lineNodeForScreenRow(2))

        expect(line2LeafNodes.length).toBe 3
        expect(line2LeafNodes[0].textContent).toBe '  '
        expect(line2LeafNodes[0].classList.contains('indent-guide')).toBe true
        expect(line2LeafNodes[1].textContent).toBe '  '
        expect(line2LeafNodes[1].classList.contains('indent-guide')).toBe true
        expect(line2LeafNodes[2].textContent).toBe '  '
        expect(line2LeafNodes[2].classList.contains('indent-guide')).toBe true

      it "renders indent guides correctly on lines containing only whitespace", ->
        editor.getBuffer().insert([1, Infinity], '\n      ')
        line2LeafNodes = getLeafNodes(component.lineNodeForScreenRow(2))
        expect(line2LeafNodes.length).toBe 3
        expect(line2LeafNodes[0].textContent).toBe '  '
        expect(line2LeafNodes[0].classList.contains('indent-guide')).toBe true
        expect(line2LeafNodes[1].textContent).toBe '  '
        expect(line2LeafNodes[1].classList.contains('indent-guide')).toBe true
        expect(line2LeafNodes[2].textContent).toBe '  '
        expect(line2LeafNodes[2].classList.contains('indent-guide')).toBe true

      it "does not render indent guides in trailing whitespace for lines containing non whitespace characters", ->
        editor.getBuffer().setText "  hi  "
        line0LeafNodes = getLeafNodes(component.lineNodeForScreenRow(0))
        expect(line0LeafNodes[0].textContent).toBe '  '
        expect(line0LeafNodes[0].classList.contains('indent-guide')).toBe true
        expect(line0LeafNodes[1].textContent).toBe '  '
        expect(line0LeafNodes[1].classList.contains('indent-guide')).toBe false

      getLeafNodes = (node) ->
        if node.children.length > 0
          flatten(toArray(node.children).map(getLeafNodes))
        else
          [node]

    describe "when the buffer contains null bytes", ->
      it "excludes the null byte from character measurement", ->
        editor.setText("a\0b")
        expect(editor.pixelPositionForScreenPosition([0, Infinity]).left).toEqual 2 * charWidth

  describe "gutter rendering", ->
    [gutter] = []

    lineNumberHasClass = (screenRow, klass) ->
      component.lineNumberNodeForScreenRow(screenRow).classList.contains(klass)

    lineNumberForBufferRowHasClass = (bufferRow, klass) ->
      screenRow = editor.displayBuffer.screenRowForBufferRow(bufferRow)
      component.lineNumberNodeForScreenRow(screenRow).classList.contains(klass)

    beforeEach ->
      {gutter} = component.refs

    it "renders the currently-visible line numbers", ->
      node.style.height = 4.5 * lineHeightInPixels + 'px'
      component.measureScrollView()

      expect(node.querySelectorAll('.line-number').length).toBe 6 + 2 + 1 # line overdraw margin below + dummy line number
      expect(component.lineNumberNodeForScreenRow(0).textContent).toBe "#{nbsp}1"
      expect(component.lineNumberNodeForScreenRow(5).textContent).toBe "#{nbsp}6"

      verticalScrollbarNode.scrollTop = 2.5 * lineHeightInPixels
      verticalScrollbarNode.dispatchEvent(new UIEvent('scroll'))

      expect(node.querySelectorAll('.line-number').length).toBe 6 + 4 + 1 # line overdraw margin above/below + dummy line number

      expect(component.lineNumberNodeForScreenRow(2).textContent).toBe "#{nbsp}3"
      expect(component.lineNumberNodeForScreenRow(2).offsetTop).toBe 2 * lineHeightInPixels
      return
      expect(component.lineNumberNodeForScreenRow(7).textContent).toBe "#{nbsp}8"
      expect(component.lineNumberNodeForScreenRow(7).offsetTop).toBe 7 * lineHeightInPixels

    it "updates the translation of subsequent line numbers when lines are inserted or removed", ->
      editor.getBuffer().insert([0, 0], '\n\n')

      lineNumberNodes = node.querySelectorAll('.line-number')
      expect(component.lineNumberNodeForScreenRow(0).offsetTop).toBe 0
      expect(component.lineNumberNodeForScreenRow(1).offsetTop).toBe 1 * lineHeightInPixels
      expect(component.lineNumberNodeForScreenRow(2).offsetTop).toBe 2 * lineHeightInPixels
      expect(component.lineNumberNodeForScreenRow(3).offsetTop).toBe 3 * lineHeightInPixels
      expect(component.lineNumberNodeForScreenRow(4).offsetTop).toBe 4 * lineHeightInPixels

      editor.getBuffer().insert([0, 0], '\n\n')
      expect(component.lineNumberNodeForScreenRow(0).offsetTop).toBe 0
      expect(component.lineNumberNodeForScreenRow(1).offsetTop).toBe 1 * lineHeightInPixels
      expect(component.lineNumberNodeForScreenRow(2).offsetTop).toBe 2 * lineHeightInPixels
      expect(component.lineNumberNodeForScreenRow(3).offsetTop).toBe 3 * lineHeightInPixels
      expect(component.lineNumberNodeForScreenRow(4).offsetTop).toBe 4 * lineHeightInPixels
      expect(component.lineNumberNodeForScreenRow(5).offsetTop).toBe 5 * lineHeightInPixels
      expect(component.lineNumberNodeForScreenRow(6).offsetTop).toBe 6 * lineHeightInPixels

    it "renders • characters for soft-wrapped lines", ->
      editor.setSoftWrap(true)
      node.style.height = 4.5 * lineHeightInPixels + 'px'
      node.style.width = 30 * charWidth + 'px'
      component.measureScrollView()

      expect(node.querySelectorAll('.line-number').length).toBe 6 + lineOverdrawMargin + 1 # 1 dummy line node
      expect(component.lineNumberNodeForScreenRow(0).textContent).toBe "#{nbsp}1"
      expect(component.lineNumberNodeForScreenRow(1).textContent).toBe "#{nbsp}•"
      expect(component.lineNumberNodeForScreenRow(2).textContent).toBe "#{nbsp}2"
      expect(component.lineNumberNodeForScreenRow(3).textContent).toBe "#{nbsp}•"
      expect(component.lineNumberNodeForScreenRow(4).textContent).toBe "#{nbsp}3"
      expect(component.lineNumberNodeForScreenRow(5).textContent).toBe "#{nbsp}•"

    it "pads line numbers to be right-justified based on the maximum number of line number digits", ->
      editor.getBuffer().setText([1..10].join('\n'))
      for screenRow in [0..8]
        expect(component.lineNumberNodeForScreenRow(screenRow).textContent).toBe "#{nbsp}#{screenRow + 1}"
      expect(component.lineNumberNodeForScreenRow(9).textContent).toBe "10"

      gutterNode = node.querySelector('.gutter')
      initialGutterWidth = gutterNode.offsetWidth

      # Removes padding when the max number of digits goes down
      editor.getBuffer().delete([[1, 0], [2, 0]])
      for screenRow in [0..8]
        expect(component.lineNumberNodeForScreenRow(screenRow).textContent).toBe "#{screenRow + 1}"
      expect(gutterNode.offsetWidth).toBeLessThan initialGutterWidth

      # Increases padding when the max number of digits goes up
      editor.getBuffer().insert([0, 0], '\n\n')
      for screenRow in [0..8]
        expect(component.lineNumberNodeForScreenRow(screenRow).textContent).toBe "#{nbsp}#{screenRow + 1}"
      expect(component.lineNumberNodeForScreenRow(9).textContent).toBe "10"
      expect(gutterNode.offsetWidth).toBe initialGutterWidth

    describe "fold decorations", ->
      describe "rendering fold decorations", ->
        it "adds the foldable class to line numbers when the line is foldable", ->
          expect(lineNumberHasClass(0, 'foldable')).toBe true
          expect(lineNumberHasClass(1, 'foldable')).toBe true
          expect(lineNumberHasClass(2, 'foldable')).toBe false
          expect(lineNumberHasClass(3, 'foldable')).toBe false
          expect(lineNumberHasClass(4, 'foldable')).toBe true
          expect(lineNumberHasClass(5, 'foldable')).toBe false

        it "updates the foldable class on the correct line numbers when the foldable positions change", ->
          editor.getBuffer().insert([0, 0], '\n')
          expect(lineNumberHasClass(0, 'foldable')).toBe false
          expect(lineNumberHasClass(1, 'foldable')).toBe true
          expect(lineNumberHasClass(2, 'foldable')).toBe true
          expect(lineNumberHasClass(3, 'foldable')).toBe false
          expect(lineNumberHasClass(4, 'foldable')).toBe false
          expect(lineNumberHasClass(5, 'foldable')).toBe true
          expect(lineNumberHasClass(6, 'foldable')).toBe false

        it "updates the foldable class on a line number that becomes foldable", ->
          expect(lineNumberHasClass(11, 'foldable')).toBe false

          editor.getBuffer().insert([11, 44], '\n    fold me')
          expect(lineNumberHasClass(11, 'foldable')).toBe true

          editor.undo()
          expect(lineNumberHasClass(11, 'foldable')).toBe false

        it "adds, updates and removes the folded class on the correct line number nodes", ->
          editor.foldBufferRow(4)
          expect(lineNumberHasClass(4, 'folded')).toBe true

          editor.getBuffer().insert([0, 0], '\n')
          expect(lineNumberHasClass(4, 'folded')).toBe false
          expect(lineNumberHasClass(5, 'folded')).toBe true

          editor.unfoldBufferRow(5)
          expect(lineNumberHasClass(5, 'folded')).toBe false

      describe "mouse interactions with fold indicators", ->
        [gutterNode] = []

        buildClickEvent = (target) ->
          buildMouseEvent('click', {target})

        beforeEach ->
          gutterNode = node.querySelector('.gutter')

        it "folds and unfolds the block represented by the fold indicator when clicked", ->
          expect(lineNumberHasClass(1, 'folded')).toBe false

          lineNumber = component.lineNumberNodeForScreenRow(1)
          target = lineNumber.querySelector('.icon-right')

          target.dispatchEvent(buildClickEvent(target))
          expect(lineNumberHasClass(1, 'folded')).toBe true

          lineNumber = component.lineNumberNodeForScreenRow(1)
          target = lineNumber.querySelector('.icon-right')

          target.dispatchEvent(buildClickEvent(target))
          expect(lineNumberHasClass(1, 'folded')).toBe false

        it "does not fold when the line number node is clicked", ->
          lineNumber = component.lineNumberNodeForScreenRow(1)
          lineNumber.dispatchEvent(buildClickEvent(lineNumber))
          expect(lineNumberHasClass(1, 'folded')).toBe false

    describe "cursor-line decorations", ->
      cursor = null
      beforeEach ->
        cursor = editor.getCursor()

      it "modifies the cursor-line decoration when the cursor moves", ->
        cursor.setScreenPosition([0, 0])
        expect(lineNumberHasClass(0, 'cursor-line')).toBe true

        cursor.setScreenPosition([1, 0])
        expect(lineNumberHasClass(0, 'cursor-line')).toBe false
        expect(lineNumberHasClass(1, 'cursor-line')).toBe true

      it "updates cursor-line decorations for multiple cursors", ->
        cursor.setScreenPosition([2, 0])
        cursor2 = editor.addCursorAtScreenPosition([8, 0])
        cursor3 = editor.addCursorAtScreenPosition([10, 0])

        expect(lineNumberHasClass(2, 'cursor-line')).toBe true
        expect(lineNumberHasClass(8, 'cursor-line')).toBe true
        expect(lineNumberHasClass(10, 'cursor-line')).toBe true

        cursor2.destroy()
        expect(lineNumberHasClass(2, 'cursor-line')).toBe true
        expect(lineNumberHasClass(8, 'cursor-line')).toBe false
        expect(lineNumberHasClass(10, 'cursor-line')).toBe true

        cursor3.destroy()
        expect(lineNumberHasClass(2, 'cursor-line')).toBe true
        expect(lineNumberHasClass(8, 'cursor-line')).toBe false
        expect(lineNumberHasClass(10, 'cursor-line')).toBe false

      it "adds cursor-line decorations to multiple lines when a selection is performed", ->
        cursor.setScreenPosition([1, 0])
        editor.selectDown(2)
        expect(lineNumberHasClass(0, 'cursor-line')).toBe false
        expect(lineNumberHasClass(1, 'cursor-line')).toBe true
        expect(lineNumberHasClass(2, 'cursor-line')).toBe true
        expect(lineNumberHasClass(3, 'cursor-line')).toBe true
        expect(lineNumberHasClass(4, 'cursor-line')).toBe false

    describe "when decorations are applied to markers", ->
      {marker, decoration} = {}
      beforeEach ->
        marker = editor.displayBuffer.markBufferRange([[2, 13], [3, 15]], class: 'my-marker', invalidate: 'inside')
        decoration = {type: 'gutter', class: 'someclass'}
        editor.addDecorationForMarker(marker, decoration)
        waitsFor -> not component.decorationChangedImmediate?

      it "does not render off-screen lines with line number classes until they are with in the rendered row range", ->
        node.style.height = 4.5 * lineHeightInPixels + 'px'
        component.measureScrollView()

        expect(component.lineNumberNodeForScreenRow(9)).not.toBeDefined()

        marker = editor.displayBuffer.markBufferRange([[9, 0], [9, 0]], invalidate: 'inside')
        editor.addDecorationForMarker(marker, type: 'gutter', class: 'fancy-class')
        editor.addDecorationForMarker(marker, type: 'someother-type', class: 'nope-class')

        verticalScrollbarNode.scrollTop = 2.5 * lineHeightInPixels
        verticalScrollbarNode.dispatchEvent(new UIEvent('scroll'))

        expect(lineNumberHasClass(9, 'fancy-class')).toBe true
        expect(lineNumberHasClass(9, 'nope-class')).toBe false

      it "renders classes on correct screen lines when the user folds a block of code", ->
        marker = editor.displayBuffer.markBufferRange([[9, 0], [9, 0]], invalidate: 'inside')
        editor.addDecorationForMarker(marker, decoration)

        waitsFor -> not component.decorationChangedImmediate?
        runs ->
          expect(lineNumberForBufferRowHasClass(9, 'someclass')).toBe true
          editor.foldBufferRow(5)
          editor.removeDecorationForMarker(marker, decoration)

        waitsFor -> not component.decorationChangedImmediate?
        runs ->
          expect(lineNumberForBufferRowHasClass(9, 'someclass')).toBe false

      it "updates line number classes when the marker moves", ->
        expect(lineNumberHasClass(1, 'someclass')).toBe false
        expect(lineNumberHasClass(2, 'someclass')).toBe true
        expect(lineNumberHasClass(3, 'someclass')).toBe true
        expect(lineNumberHasClass(4, 'someclass')).toBe false

        editor.getBuffer().insert([0, 0], '\n')

        waitsFor -> not component.decorationChangedImmediate?
        runs ->
          expect(lineNumberHasClass(2, 'someclass')).toBe false
          expect(lineNumberHasClass(3, 'someclass')).toBe true
          expect(lineNumberHasClass(4, 'someclass')).toBe true
          expect(lineNumberHasClass(5, 'someclass')).toBe false

          editor.getBuffer().deleteRows(0, 1)

        waitsFor -> not component.decorationChangedImmediate?
        runs ->
          expect(lineNumberHasClass(0, 'someclass')).toBe false
          expect(lineNumberHasClass(1, 'someclass')).toBe true
          expect(lineNumberHasClass(2, 'someclass')).toBe true
          expect(lineNumberHasClass(3, 'someclass')).toBe false

      it "removes line number classes when a decoration's marker is invalidated", ->
        editor.getBuffer().insert([3, 2], 'n')

        waitsFor -> not component.decorationChangedImmediate?
        runs ->

          expect(marker.isValid()).toBe false
          expect(lineNumberHasClass(1, 'someclass')).toBe false
          expect(lineNumberHasClass(2, 'someclass')).toBe false
          expect(lineNumberHasClass(3, 'someclass')).toBe false
          expect(lineNumberHasClass(4, 'someclass')).toBe false

          editor.getBuffer().undo()

        waitsFor -> not component.decorationChangedImmediate?
        runs ->
          expect(marker.isValid()).toBe true
          expect(lineNumberHasClass(1, 'someclass')).toBe false
          expect(lineNumberHasClass(2, 'someclass')).toBe true
          expect(lineNumberHasClass(3, 'someclass')).toBe true
          expect(lineNumberHasClass(4, 'someclass')).toBe false

      it "removes the classes and unsubscribes from the marker when decoration is removed", ->
        editor.removeDecorationForMarker(marker, decoration)

        waitsFor -> not component.decorationChangedImmediate?
        runs ->
          expect(lineNumberHasClass(1, 'someclass')).toBe false
          expect(lineNumberHasClass(2, 'someclass')).toBe false
          expect(lineNumberHasClass(3, 'someclass')).toBe false
          expect(lineNumberHasClass(4, 'someclass')).toBe false

        editor.getBuffer().insert([0, 0], '\n')

        waitsFor -> not component.decorationChangedImmediate?
        runs ->
          expect(lineNumberHasClass(2, 'someclass')).toBe false
          expect(lineNumberHasClass(3, 'someclass')).toBe false

      it "removes the line number classes when the decoration's marker is destroyed", ->
        marker.destroy()

        waitsFor -> not component.decorationChangedImmediate?
        runs ->
          expect(lineNumberHasClass(1, 'someclass')).toBe false
          expect(lineNumberHasClass(2, 'someclass')).toBe false
          expect(lineNumberHasClass(3, 'someclass')).toBe false
          expect(lineNumberHasClass(4, 'someclass')).toBe false

      describe "when soft wrapping is enabled", ->
        beforeEach ->
          editor.setText "a line that wraps, ok"
          editor.setSoftWrap(true)
          node.style.width = 16 * charWidth + 'px'
          component.measureScrollView()

        it "applies decoration only to the first row when marker range does not wrap", ->
          marker = editor.displayBuffer.markBufferRange([[0, 0], [0, 0]])
          editor.addDecorationForMarker(marker, type: 'gutter', class: 'someclass')

          waitsFor -> not component.decorationChangedImmediate?
          runs ->
            expect(lineNumberHasClass(0, 'someclass')).toBe true
            expect(lineNumberHasClass(1, 'someclass')).toBe false

        it "applies decoration to both rows when marker wraps", ->
          marker = editor.displayBuffer.markBufferRange([[0, 0], [0, Infinity]])
          editor.addDecorationForMarker(marker, type: 'gutter', class: 'someclass')

          waitsFor -> not component.decorationChangedImmediate?
          runs ->
            expect(lineNumberHasClass(0, 'someclass')).toBe true
            expect(lineNumberHasClass(1, 'someclass')).toBe true

  describe "cursor rendering", ->
    it "renders the currently visible cursors, translated relative to the scroll position", ->
      cursor1 = editor.getCursor()
      cursor1.setScreenPosition([0, 5])

      node.style.height = 4.5 * lineHeightInPixels + 'px'
      node.style.width = 20 * lineHeightInPixels + 'px'
      component.measureScrollView()

      cursorNodes = node.querySelectorAll('.cursor')
      expect(cursorNodes.length).toBe 1
      expect(cursorNodes[0].offsetHeight).toBe lineHeightInPixels
      expect(cursorNodes[0].offsetWidth).toBe charWidth
      expect(cursorNodes[0].style['-webkit-transform']).toBe "translate3d(#{5 * charWidth}px, #{0 * lineHeightInPixels}px, 0px)"

      cursor2 = editor.addCursorAtScreenPosition([8, 11])
      cursor3 = editor.addCursorAtScreenPosition([4, 10])

      cursorNodes = node.querySelectorAll('.cursor')
      expect(cursorNodes.length).toBe 2
      expect(cursorNodes[0].offsetTop).toBe 0
      expect(cursorNodes[0].style['-webkit-transform']).toBe "translate3d(#{5 * charWidth}px, #{0 * lineHeightInPixels}px, 0px)"
      expect(cursorNodes[1].style['-webkit-transform']).toBe "translate3d(#{10 * charWidth}px, #{4 * lineHeightInPixels}px, 0px)"

      verticalScrollbarNode.scrollTop = 4.5 * lineHeightInPixels
      verticalScrollbarNode.dispatchEvent(new UIEvent('scroll'))
      horizontalScrollbarNode.scrollLeft = 3.5 * charWidth
      horizontalScrollbarNode.dispatchEvent(new UIEvent('scroll'))

      cursorNodes = node.querySelectorAll('.cursor')
      expect(cursorNodes.length).toBe 2
      expect(cursorNodes[0].style['-webkit-transform']).toBe "translate3d(#{(11 - 3.5) * charWidth}px, #{(8 - 4.5) * lineHeightInPixels}px, 0px)"
      expect(cursorNodes[1].style['-webkit-transform']).toBe "translate3d(#{(10 - 3.5) * charWidth}px, #{(4 - 4.5) * lineHeightInPixels}px, 0px)"

      cursor3.destroy()
      cursorNodes = node.querySelectorAll('.cursor')
      expect(cursorNodes.length).toBe 1
      expect(cursorNodes[0].style['-webkit-transform']).toBe "translate3d(#{(11 - 3.5) * charWidth}px, #{(6 - 2.5) * lineHeightInPixels}px, 0px)"

    it "accounts for character widths when positioning cursors", ->
      atom.config.set('editor.fontFamily', 'sans-serif')
      editor.setCursorScreenPosition([0, 16])

      cursor = node.querySelector('.cursor')
      cursorRect = cursor.getBoundingClientRect()

      cursorLocationTextNode = component.lineNodeForScreenRow(0).querySelector('.storage.type.function.js').firstChild
      range = document.createRange()
      range.setStart(cursorLocationTextNode, 0)
      range.setEnd(cursorLocationTextNode, 1)
      rangeRect = range.getBoundingClientRect()

      expect(cursorRect.left).toBe rangeRect.left
      expect(cursorRect.width).toBe rangeRect.width

    it "sets the cursor to the default character width at the end of a line", ->
      editor.setCursorScreenPosition([0, Infinity])
      cursorNode = node.querySelector('.cursor')
      expect(cursorNode.offsetWidth).toBe charWidth

    it "gives the cursor a non-zero width even if it's inside atomic tokens", ->
      editor.setCursorScreenPosition([1, 0])
      cursorNode = node.querySelector('.cursor')
      expect(cursorNode.offsetWidth).toBe charWidth

    it "blinks cursors when they aren't moving", ->
      spyOn(_._, 'now').andCallFake -> window.now # Ensure _.debounce is based on our fake spec timeline
      cursorsNode = node.querySelector('.cursors')

      expect(cursorsNode.classList.contains('blink-off')).toBe false
      advanceClock(component.props.cursorBlinkPeriod / 2)
      expect(cursorsNode.classList.contains('blink-off')).toBe true

      advanceClock(component.props.cursorBlinkPeriod / 2)
      expect(cursorsNode.classList.contains('blink-off')).toBe false

      # Stop blinking after moving the cursor
      editor.moveCursorRight()
      expect(cursorsNode.classList.contains('blink-off')).toBe false

      advanceClock(component.props.cursorBlinkResumeDelay)
      advanceClock(component.props.cursorBlinkPeriod / 2)
      expect(cursorsNode.classList.contains('blink-off')).toBe true

    it "does not render cursors that are associated with non-empty selections", ->
      editor.setSelectedScreenRange([[0, 4], [4, 6]])
      editor.addCursorAtScreenPosition([6, 8])

      cursorNodes = node.querySelectorAll('.cursor')
      expect(cursorNodes.length).toBe 1
      expect(cursorNodes[0].style['-webkit-transform']).toBe "translate3d(#{8 * charWidth}px, #{6 * lineHeightInPixels}px, 0px)"

    it "updates cursor positions when the line height changes", ->
      editor.setCursorBufferPosition([1, 10])
      component.setLineHeight(2)
      cursorNode = node.querySelector('.cursor')
      expect(cursorNode.style['-webkit-transform']).toBe "translate3d(#{10 * editor.getDefaultCharWidth()}px, #{editor.getLineHeightInPixels()}px, 0px)"

    it "updates cursor positions when the font size changes", ->
      editor.setCursorBufferPosition([1, 10])
      component.setFontSize(10)
      cursorNode = node.querySelector('.cursor')
      expect(cursorNode.style['-webkit-transform']).toBe "translate3d(#{10 * editor.getDefaultCharWidth()}px, #{editor.getLineHeightInPixels()}px, 0px)"

    it "updates cursor positions when the font family changes", ->
      editor.setCursorBufferPosition([1, 10])
      component.setFontFamily('sans-serif')
      cursorNode = node.querySelector('.cursor')

      {left} = editor.pixelPositionForScreenPosition([1, 10])
      expect(cursorNode.style['-webkit-transform']).toBe "translate3d(#{left}px, #{editor.getLineHeightInPixels()}px, 0px)"

  describe "selection rendering", ->
    [scrollViewNode, scrollViewClientLeft] = []

    beforeEach ->
      scrollViewNode = node.querySelector('.scroll-view')
      scrollViewClientLeft = node.querySelector('.scroll-view').getBoundingClientRect().left

    it "renders 1 region for 1-line selections", ->
      # 1-line selection
      editor.setSelectedScreenRange([[1, 6], [1, 10]])
      regions = node.querySelectorAll('.selection .region')

      expect(regions.length).toBe 1
      regionRect = regions[0].getBoundingClientRect()
      expect(regionRect.top).toBe 1 * lineHeightInPixels
      expect(regionRect.height).toBe 1 * lineHeightInPixels
      expect(regionRect.left).toBe scrollViewClientLeft + 6 * charWidth
      expect(regionRect.width).toBe 4 * charWidth

    it "renders 2 regions for 2-line selections", ->
      editor.setSelectedScreenRange([[1, 6], [2, 10]])
      regions = node.querySelectorAll('.selection .region')
      expect(regions.length).toBe 2

      region1Rect = regions[0].getBoundingClientRect()
      expect(region1Rect.top).toBe 1 * lineHeightInPixels
      expect(region1Rect.height).toBe 1 * lineHeightInPixels
      expect(region1Rect.left).toBe scrollViewClientLeft + 6 * charWidth
      expect(region1Rect.right).toBe scrollViewNode.getBoundingClientRect().right

      region2Rect = regions[1].getBoundingClientRect()
      expect(region2Rect.top).toBe 2 * lineHeightInPixels
      expect(region2Rect.height).toBe 1 * lineHeightInPixels
      expect(region2Rect.left).toBe scrollViewClientLeft + 0
      expect(region2Rect.width).toBe 10 * charWidth

    it "renders 3 regions for selections with more than 2 lines", ->
      editor.setSelectedScreenRange([[1, 6], [5, 10]])
      regions = node.querySelectorAll('.selection .region')
      expect(regions.length).toBe 3

      region1Rect = regions[0].getBoundingClientRect()
      expect(region1Rect.top).toBe 1 * lineHeightInPixels
      expect(region1Rect.height).toBe 1 * lineHeightInPixels
      expect(region1Rect.left).toBe scrollViewClientLeft + 6 * charWidth
      expect(region1Rect.right).toBe scrollViewNode.getBoundingClientRect().right

      region2Rect = regions[1].getBoundingClientRect()
      expect(region2Rect.top).toBe 2 * lineHeightInPixels
      expect(region2Rect.height).toBe 3 * lineHeightInPixels
      expect(region2Rect.left).toBe scrollViewClientLeft + 0
      expect(region2Rect.right).toBe scrollViewNode.getBoundingClientRect().right

      region3Rect = regions[2].getBoundingClientRect()
      expect(region3Rect.top).toBe 5 * lineHeightInPixels
      expect(region3Rect.height).toBe 1 * lineHeightInPixels
      expect(region3Rect.left).toBe scrollViewClientLeft + 0
      expect(region3Rect.width).toBe 10 * charWidth

    it "does not render empty selections", ->
      editor.addSelectionForBufferRange([[2, 2], [2, 2]])
      expect(editor.getSelection(0).isEmpty()).toBe true
      expect(editor.getSelection(1).isEmpty()).toBe true

      expect(node.querySelectorAll('.selection').length).toBe 0

    it "updates selections when the line height changes", ->
      editor.setSelectedBufferRange([[1, 6], [1, 10]])
      component.setLineHeight(2)
      selectionNode = node.querySelector('.region')
      expect(selectionNode.offsetTop).toBe editor.getLineHeightInPixels()

    it "updates selections when the font size changes", ->
      editor.setSelectedBufferRange([[1, 6], [1, 10]])
      component.setFontSize(10)
      selectionNode = node.querySelector('.region')
      expect(selectionNode.offsetTop).toBe editor.getLineHeightInPixels()
      expect(selectionNode.offsetLeft).toBe 6 * editor.getDefaultCharWidth()

    it "updates selections when the font family changes", ->
      editor.setSelectedBufferRange([[1, 6], [1, 10]])
      component.setFontFamily('sans-serif')
      selectionNode = node.querySelector('.region')
      expect(selectionNode.offsetTop).toBe editor.getLineHeightInPixels()
      expect(selectionNode.offsetLeft).toBe editor.pixelPositionForScreenPosition([1, 6]).left

  describe "highlight decoration rendering", ->
    [marker, decoration, scrollViewClientLeft] = []
    beforeEach ->
      scrollViewClientLeft = node.querySelector('.scroll-view').getBoundingClientRect().left
      marker = editor.displayBuffer.markBufferRange([[2, 13], [3, 15]], invalidate: 'inside')
      decoration = {type: 'highlight', class: 'test-highlight'}
      editor.addDecorationForMarker(marker, decoration)
      waitsFor -> not component.decorationChangedImmediate?

    it "does not render highlights for off-screen lines until they come on-screen", ->
      node.style.height = 2.5 * lineHeightInPixels + 'px'
      component.measureScrollView()

      marker = editor.displayBuffer.markBufferRange([[9, 2], [9, 4]], invalidate: 'inside')
      editor.addDecorationForMarker(marker, type: 'highlight', class: 'some-highlight')

      waitsFor -> not component.decorationChangedImmediate?
      runs ->
        # Should not be rendering range containing the marker
        expect(component.getRenderedRowRange()[1]).toBeLessThan 9

        regions = node.querySelectorAll('.some-highlight .region')

        # Nothing when outside the rendered row range
        expect(regions.length).toBe 0

        verticalScrollbarNode.scrollTop = 3.5 * lineHeightInPixels
        verticalScrollbarNode.dispatchEvent(new UIEvent('scroll'))

        regions = node.querySelectorAll('.some-highlight .region')

        expect(regions.length).toBe 1
        regionRect = regions[0].style
        expect(regionRect.top).toBe 9 * lineHeightInPixels + 'px'
        expect(regionRect.height).toBe 1 * lineHeightInPixels + 'px'
        expect(regionRect.left).toBe 2 * charWidth + 'px'
        expect(regionRect.width).toBe 2 * charWidth + 'px'

    it "renders highlights decoration's marker is added", ->
      regions = node.querySelectorAll('.test-highlight .region')
      expect(regions.length).toBe 2

    it "removes highlights when a decoration is removed", ->
      editor.removeDecorationForMarker(marker, decoration)

      waitsFor -> not component.decorationChangedImmediate?
      runs ->
        regions = node.querySelectorAll('.test-highlight .region')
        expect(regions.length).toBe 0

    it "does not render a highlight that is within a fold", ->
      editor.foldBufferRow(1)

      waitsFor -> not component.decorationChangedImmediate?
      runs ->
        expect(node.querySelectorAll('.test-highlight').length).toBe 0

    it "moves rendered highlights when the marker moves", ->
      regionStyle = node.querySelector('.test-highlight .region').style
      originalTop = parseInt(regionStyle.top)

      editor.getBuffer().insert([0, 0], '\n')

      regionStyle = node.querySelector('.test-highlight .region').style
      newTop = parseInt(regionStyle.top)

      expect(newTop).toBe originalTop + lineHeightInPixels

    it "removes highlights when a decoration's marker is destroyed", ->
      marker.destroy()

      waitsFor -> not component.decorationChangedImmediate?
      runs ->
        regions = node.querySelectorAll('.test-highlight .region')
        expect(regions.length).toBe 0

    it "only renders highlights when a decoration's marker is valid", ->
      editor.getBuffer().insert([3, 2], 'n')

      waitsFor -> not component.decorationChangedImmediate?
      runs ->
        expect(marker.isValid()).toBe false
        regions = node.querySelectorAll('.test-highlight .region')
        expect(regions.length).toBe 0

        editor.getBuffer().undo()

      waitsFor -> not component.decorationChangedImmediate?
      runs ->
        expect(marker.isValid()).toBe true
        regions = node.querySelectorAll('.test-highlight .region')
        expect(regions.length).toBe 2

  describe "hidden input field", ->
    it "renders the hidden input field at the position of the last cursor if the cursor is on screen and the editor is focused", ->
      editor.setVerticalScrollMargin(0)
      editor.setHorizontalScrollMargin(0)

      inputNode = node.querySelector('.hidden-input')
      node.style.height = 5 * lineHeightInPixels + 'px'
      node.style.width = 10 * charWidth + 'px'
      component.measureScrollView()

      expect(editor.getCursorScreenPosition()).toEqual [0, 0]
      editor.setScrollTop(3 * lineHeightInPixels)
      editor.setScrollLeft(3 * charWidth)

      expect(inputNode.offsetTop).toBe 0
      expect(inputNode.offsetLeft).toBe 0

      # In bounds, not focused
      editor.setCursorBufferPosition([5, 4])
      expect(inputNode.offsetTop).toBe 0
      expect(inputNode.offsetLeft).toBe 0

      # In bounds and focused
      inputNode.focus()
      expect(inputNode.offsetTop).toBe (5 * lineHeightInPixels) - editor.getScrollTop()
      expect(inputNode.offsetLeft).toBe (4 * charWidth) - editor.getScrollLeft()

      # In bounds, not focused
      inputNode.blur()
      expect(inputNode.offsetTop).toBe 0
      expect(inputNode.offsetLeft).toBe 0

      # Out of bounds, not focused
      editor.setCursorBufferPosition([1, 2])
      expect(inputNode.offsetTop).toBe 0
      expect(inputNode.offsetLeft).toBe 0

      # Out of bounds, focused
      inputNode.focus()
      expect(inputNode.offsetTop).toBe 0
      expect(inputNode.offsetLeft).toBe 0

  describe "mouse interactions", ->
    linesNode = null

    beforeEach ->
      delayAnimationFrames = true
      linesNode = node.querySelector('.lines')

    describe "when a non-folded line is single-clicked", ->
      describe "when no modifier keys are held down", ->
        it "moves the cursor to the nearest screen position", ->
          node.style.height = 4.5 * lineHeightInPixels + 'px'
          node.style.width = 10 * charWidth + 'px'
          component.measureScrollView()
          editor.setScrollTop(3.5 * lineHeightInPixels)
          editor.setScrollLeft(2 * charWidth)

          linesNode.dispatchEvent(buildMouseEvent('mousedown', clientCoordinatesForScreenPosition([4, 8])))
          expect(editor.getCursorScreenPosition()).toEqual [4, 8]

      describe "when the shift key is held down", ->
        it "selects to the nearest screen position", ->
          editor.setCursorScreenPosition([3, 4])
          linesNode.dispatchEvent(buildMouseEvent('mousedown', clientCoordinatesForScreenPosition([5, 6]), shiftKey: true))
          expect(editor.getSelectedScreenRange()).toEqual [[3, 4], [5, 6]]

      describe "when the command key is held down", ->
        it "adds a cursor at the nearest screen position", ->
          editor.setCursorScreenPosition([3, 4])
          linesNode.dispatchEvent(buildMouseEvent('mousedown', clientCoordinatesForScreenPosition([5, 6]), metaKey: true))
          expect(editor.getSelectedScreenRanges()).toEqual [[[3, 4], [3, 4]], [[5, 6], [5, 6]]]

    describe "when a non-folded line is double-clicked", ->
      it "selects the word containing the nearest screen position", ->
        linesNode.dispatchEvent(buildMouseEvent('mousedown', clientCoordinatesForScreenPosition([5, 10]), detail: 2))
        linesNode.dispatchEvent(buildMouseEvent('mouseup'))
        expect(editor.getSelectedScreenRange()).toEqual [[5, 6], [5, 13]]

        linesNode.dispatchEvent(buildMouseEvent('mousedown', clientCoordinatesForScreenPosition([6, 6]), detail: 1))
        linesNode.dispatchEvent(buildMouseEvent('mouseup'))
        expect(editor.getSelectedScreenRange()).toEqual [[6, 6], [6, 6]]

        linesNode.dispatchEvent(buildMouseEvent('mousedown', clientCoordinatesForScreenPosition([8, 8]), detail: 1, shiftKey: true))
        linesNode.dispatchEvent(buildMouseEvent('mouseup'))
        expect(editor.getSelectedScreenRange()).toEqual [[6, 6], [8, 8]]

    describe "when a non-folded line is triple-clicked", ->
      it "selects the line containing the nearest screen position", ->
        linesNode.dispatchEvent(buildMouseEvent('mousedown', clientCoordinatesForScreenPosition([5, 10]), detail: 3))
        linesNode.dispatchEvent(buildMouseEvent('mouseup'))
        expect(editor.getSelectedScreenRange()).toEqual [[5, 0], [6, 0]]

        linesNode.dispatchEvent(buildMouseEvent('mousedown', clientCoordinatesForScreenPosition([6, 6]), detail: 1, shiftKey: true))
        linesNode.dispatchEvent(buildMouseEvent('mouseup'))
        expect(editor.getSelectedScreenRange()).toEqual [[5, 0], [7, 0]]

        linesNode.dispatchEvent(buildMouseEvent('mousedown', clientCoordinatesForScreenPosition([7, 5]), detail: 1))
        linesNode.dispatchEvent(buildMouseEvent('mouseup'))
        linesNode.dispatchEvent(buildMouseEvent('mousedown', clientCoordinatesForScreenPosition([8, 8]), detail: 1, shiftKey: true))
        linesNode.dispatchEvent(buildMouseEvent('mouseup'))
        expect(editor.getSelectedScreenRange()).toEqual [[7, 5], [8, 8]]

    describe "when the mouse is clicked and dragged", ->
      it "selects to the nearest screen position until the mouse button is released", ->
        linesNode.dispatchEvent(buildMouseEvent('mousedown', clientCoordinatesForScreenPosition([2, 4]), which: 1))
        linesNode.dispatchEvent(buildMouseEvent('mousemove', clientCoordinatesForScreenPosition([6, 8]), which: 1))
        nextAnimationFrame()
        expect(editor.getSelectedScreenRange()).toEqual [[2, 4], [6, 8]]

        linesNode.dispatchEvent(buildMouseEvent('mousemove', clientCoordinatesForScreenPosition([10, 0]), which: 1))
        nextAnimationFrame()
        expect(editor.getSelectedScreenRange()).toEqual [[2, 4], [10, 0]]

        linesNode.dispatchEvent(buildMouseEvent('mouseup'))
        linesNode.dispatchEvent(buildMouseEvent('mousemove', clientCoordinatesForScreenPosition([12, 0]), which: 1))
        nextAnimationFrame()
        expect(editor.getSelectedScreenRange()).toEqual [[2, 4], [10, 0]]

      it "stops selecting if the mouse is dragged into the dev tools", ->
        linesNode.dispatchEvent(buildMouseEvent('mousedown', clientCoordinatesForScreenPosition([2, 4]), which: 1))
        linesNode.dispatchEvent(buildMouseEvent('mousemove', clientCoordinatesForScreenPosition([6, 8]), which: 1))
        nextAnimationFrame()
        expect(editor.getSelectedScreenRange()).toEqual [[2, 4], [6, 8]]

        linesNode.dispatchEvent(buildMouseEvent('mousemove', clientCoordinatesForScreenPosition([10, 0]), which: 0))
        nextAnimationFrame()
        expect(editor.getSelectedScreenRange()).toEqual [[2, 4], [6, 8]]

        linesNode.dispatchEvent(buildMouseEvent('mousemove', clientCoordinatesForScreenPosition([8, 0]), which: 1))
        nextAnimationFrame()
        expect(editor.getSelectedScreenRange()).toEqual [[2, 4], [6, 8]]

    clientCoordinatesForScreenPosition = (screenPosition) ->
      positionOffset = editor.pixelPositionForScreenPosition(screenPosition)
      scrollViewClientRect = node.querySelector('.scroll-view').getBoundingClientRect()
      clientX = scrollViewClientRect.left + positionOffset.left - editor.getScrollLeft()
      clientY = scrollViewClientRect.top + positionOffset.top - editor.getScrollTop()
      {clientX, clientY}

  describe "focus handling", ->
    inputNode = null

    beforeEach ->
      inputNode = node.querySelector('.hidden-input')

    it "transfers focus to the hidden input", ->
      expect(document.activeElement).toBe document.body
      node.focus()
      expect(document.activeElement).toBe inputNode

    it "adds the 'is-focused' class to the editor when the hidden input is focused", ->
      expect(document.activeElement).toBe document.body
      inputNode.focus()
      expect(node.classList.contains('is-focused')).toBe true
      expect(wrapperView.hasClass('is-focused')).toBe true
      inputNode.blur()
      expect(node.classList.contains('is-focused')).toBe false
      expect(wrapperView.hasClass('is-focused')).toBe false

  describe "selection handling", ->
    cursor = null

    beforeEach ->
      cursor = editor.getCursor()
      cursor.setScreenPosition([0, 0])

    it "adds the 'has-selection' class to the editor when there is a selection", ->
      expect(node.classList.contains('has-selection')).toBe false

      editor.selectDown()
      expect(node.classList.contains('has-selection')).toBe true

      cursor.moveDown()
      expect(node.classList.contains('has-selection')).toBe false

  describe "scrolling", ->
    it "updates the vertical scrollbar when the scrollTop is changed in the model", ->
      node.style.height = 4.5 * lineHeightInPixels + 'px'
      component.measureScrollView()

      expect(verticalScrollbarNode.scrollTop).toBe 0

      editor.setScrollTop(10)
      expect(verticalScrollbarNode.scrollTop).toBe 10

    it "updates the horizontal scrollbar and the x transform of the lines based on the scrollLeft of the model", ->
      node.style.width = 30 * charWidth + 'px'
      component.measureScrollView()

      linesNode = node.querySelector('.lines')
      expect(linesNode.style['-webkit-transform']).toBe "translate3d(0px, 0px, 0px)"
      expect(horizontalScrollbarNode.scrollLeft).toBe 0

      editor.setScrollLeft(100)
      expect(linesNode.style['-webkit-transform']).toBe "translate3d(-100px, 0px, 0px)"
      expect(horizontalScrollbarNode.scrollLeft).toBe 100

    it "updates the scrollLeft of the model when the scrollLeft of the horizontal scrollbar changes", ->
      node.style.width = 30 * charWidth + 'px'
      component.measureScrollView()

      expect(editor.getScrollLeft()).toBe 0
      horizontalScrollbarNode.scrollLeft = 100
      horizontalScrollbarNode.dispatchEvent(new UIEvent('scroll'))

      expect(editor.getScrollLeft()).toBe 100

    it "does not obscure the last line with the horizontal scrollbar", ->
      node.style.height = 4.5 * lineHeightInPixels + 'px'
      node.style.width = 10 * charWidth + 'px'
      component.measureScrollView()
      editor.setScrollBottom(editor.getScrollHeight())
      lastLineNode = component.lineNodeForScreenRow(editor.getLastScreenRow())
      bottomOfLastLine = lastLineNode.getBoundingClientRect().bottom
      topOfHorizontalScrollbar = horizontalScrollbarNode.getBoundingClientRect().top
      expect(bottomOfLastLine).toBe topOfHorizontalScrollbar

      # Scroll so there's no space below the last line when the horizontal scrollbar disappears
      node.style.width = 100 * charWidth + 'px'
      component.measureScrollView()
      bottomOfLastLine = lastLineNode.getBoundingClientRect().bottom
      bottomOfEditor = node.getBoundingClientRect().bottom
      expect(bottomOfLastLine).toBe bottomOfEditor

    it "does not obscure the last character of the longest line with the vertical scrollbar", ->
      node.style.height = 7 * lineHeightInPixels + 'px'
      node.style.width = 10 * charWidth + 'px'
      component.measureScrollView()

      editor.setScrollLeft(Infinity)

      rightOfLongestLine = component.lineNodeForScreenRow(6).getBoundingClientRect().right
      leftOfVerticalScrollbar = verticalScrollbarNode.getBoundingClientRect().left
      expect(Math.round(rightOfLongestLine)).toBe leftOfVerticalScrollbar - 1 # Leave 1 px so the cursor is visible on the end of the line

    it "only displays dummy scrollbars when scrollable in that direction", ->
      expect(verticalScrollbarNode.style.display).toBe 'none'
      expect(horizontalScrollbarNode.style.display).toBe 'none'

      node.style.height = 4.5 * lineHeightInPixels + 'px'
      node.style.width = '1000px'
      component.measureScrollView()

      expect(verticalScrollbarNode.style.display).toBe ''
      expect(horizontalScrollbarNode.style.display).toBe 'none'

      node.style.width = 10 * charWidth + 'px'
      component.measureScrollView()

      expect(verticalScrollbarNode.style.display).toBe ''
      expect(horizontalScrollbarNode.style.display).toBe ''

      node.style.height = 20 * lineHeightInPixels + 'px'
      component.measureScrollView()

      expect(verticalScrollbarNode.style.display).toBe 'none'
      expect(horizontalScrollbarNode.style.display).toBe ''

    it "makes the dummy scrollbar divs only as tall/wide as the actual scrollbars", ->
      node.style.height = 4 * lineHeightInPixels + 'px'
      node.style.width = 10 * charWidth + 'px'
      component.measureScrollView()

      atom.themes.applyStylesheet "test", """
        ::-webkit-scrollbar {
          width: 8px;
          height: 8px;
        }
      """

      scrollbarCornerNode = node.querySelector('.scrollbar-corner')
      expect(verticalScrollbarNode.offsetWidth).toBe 8
      expect(horizontalScrollbarNode.offsetHeight).toBe 8
      expect(scrollbarCornerNode.offsetWidth).toBe 8
      expect(scrollbarCornerNode.offsetHeight).toBe 8

    it "assigns the bottom/right of the scrollbars to the width of the opposite scrollbar if it is visible", ->
      scrollbarCornerNode = node.querySelector('.scrollbar-corner')

      expect(verticalScrollbarNode.style.bottom).toBe ''
      expect(horizontalScrollbarNode.style.right).toBe ''

      node.style.height = 4.5 * lineHeightInPixels + 'px'
      node.style.width = '1000px'
      component.measureScrollView()
      expect(verticalScrollbarNode.style.bottom).toBe ''
      expect(horizontalScrollbarNode.style.right).toBe verticalScrollbarNode.offsetWidth + 'px'
      expect(scrollbarCornerNode.style.display).toBe 'none'

      node.style.width = 10 * charWidth + 'px'
      component.measureScrollView()
      expect(verticalScrollbarNode.style.bottom).toBe horizontalScrollbarNode.offsetHeight + 'px'
      expect(horizontalScrollbarNode.style.right).toBe verticalScrollbarNode.offsetWidth + 'px'
      expect(scrollbarCornerNode.style.display).toBe ''

      node.style.height = 20 * lineHeightInPixels + 'px'
      component.measureScrollView()
      expect(verticalScrollbarNode.style.bottom).toBe horizontalScrollbarNode.offsetHeight + 'px'
      expect(horizontalScrollbarNode.style.right).toBe ''
      expect(scrollbarCornerNode.style.display).toBe 'none'

    it "accounts for the width of the gutter in the scrollWidth of the horizontal scrollbar", ->
      gutterNode = node.querySelector('.gutter')
      node.style.width = 10 * charWidth + 'px'
      component.measureScrollView()

      expect(horizontalScrollbarNode.scrollWidth).toBe gutterNode.offsetWidth + editor.getScrollWidth()

  describe "mousewheel events", ->
    beforeEach ->
      atom.config.set('editor.scrollSensitivity', 100)

    describe "updating scrollTop and scrollLeft", ->
      beforeEach ->
        node.style.height = 4.5 * lineHeightInPixels + 'px'
        node.style.width = 20 * charWidth + 'px'
        component.measureScrollView()

      it "updates the scrollLeft or scrollTop on mousewheel events depending on which delta is greater (x or y)", ->
        expect(verticalScrollbarNode.scrollTop).toBe 0
        expect(horizontalScrollbarNode.scrollLeft).toBe 0

        node.dispatchEvent(new WheelEvent('mousewheel', wheelDeltaX: -5, wheelDeltaY: -10))
        expect(verticalScrollbarNode.scrollTop).toBe 10
        expect(horizontalScrollbarNode.scrollLeft).toBe 0

        node.dispatchEvent(new WheelEvent('mousewheel', wheelDeltaX: -15, wheelDeltaY: -5))
        expect(verticalScrollbarNode.scrollTop).toBe 10
        expect(horizontalScrollbarNode.scrollLeft).toBe 15

      it "updates the scrollLeft or scrollTop according to the scroll sensitivity", ->
        atom.config.set('editor.scrollSensitivity', 50)
        node.dispatchEvent(new WheelEvent('mousewheel', wheelDeltaX: -5, wheelDeltaY: -10))
        expect(verticalScrollbarNode.scrollTop).toBe 5
        expect(horizontalScrollbarNode.scrollLeft).toBe 0

        node.dispatchEvent(new WheelEvent('mousewheel', wheelDeltaX: -15, wheelDeltaY: -5))
        expect(verticalScrollbarNode.scrollTop).toBe 5
        expect(horizontalScrollbarNode.scrollLeft).toBe 7

      it "uses the previous scrollSensitivity when the value is not an int", ->
        atom.config.set('editor.scrollSensitivity', 'nope')
        node.dispatchEvent(new WheelEvent('mousewheel', wheelDeltaX: 0, wheelDeltaY: -10))
        expect(verticalScrollbarNode.scrollTop).toBe 10

      it "parses negative scrollSensitivity values as positive", ->
        atom.config.set('editor.scrollSensitivity', -50)
        node.dispatchEvent(new WheelEvent('mousewheel', wheelDeltaX: 0, wheelDeltaY: -10))
        expect(verticalScrollbarNode.scrollTop).toBe 5

    describe "when the mousewheel event's target is a line", ->
      it "keeps the line on the DOM if it is scrolled off-screen", ->
        node.style.height = 4.5 * lineHeightInPixels + 'px'
        node.style.width = 20 * charWidth + 'px'
        component.measureScrollView()

        lineNode = node.querySelector('.line')
        wheelEvent = new WheelEvent('mousewheel', wheelDeltaX: 0, wheelDeltaY: -500)
        Object.defineProperty(wheelEvent, 'target', get: -> lineNode)
        node.dispatchEvent(wheelEvent)

        expect(node.contains(lineNode)).toBe true

      it "does not set the mouseWheelScreenRow if scrolling horizontally", ->
        node.style.height = 4.5 * lineHeightInPixels + 'px'
        node.style.width = 20 * charWidth + 'px'
        component.measureScrollView()

        lineNode = node.querySelector('.line')
        wheelEvent = new WheelEvent('mousewheel', wheelDeltaX: 10, wheelDeltaY: 0)
        Object.defineProperty(wheelEvent, 'target', get: -> lineNode)
        node.dispatchEvent(wheelEvent)

        expect(component.mouseWheelScreenRow).toBe null

      it "clears the mouseWheelScreenRow after a delay even if the event does not cause scrolling", ->
        spyOn(_._, 'now').andCallFake -> window.now # Ensure _.debounce is based on our fake spec timeline

        expect(editor.getScrollTop()).toBe 0

        lineNode = node.querySelector('.line')
        wheelEvent = new WheelEvent('mousewheel', wheelDeltaX: 0, wheelDeltaY: 10)
        Object.defineProperty(wheelEvent, 'target', get: -> lineNode)
        node.dispatchEvent(wheelEvent)

        expect(editor.getScrollTop()).toBe 0

        expect(component.mouseWheelScreenRow).toBe 0
        advanceClock(component.mouseWheelScreenRowClearDelay)
        expect(component.mouseWheelScreenRow).toBe null

      it "does not preserve the line if it is on screen", ->
        expect(node.querySelectorAll('.line-number').length).toBe 14 # dummy line
        lineNodes = node.querySelectorAll('.line')
        expect(lineNodes.length).toBe 13
        lineNode = lineNodes[0]

        wheelEvent = new WheelEvent('mousewheel', wheelDeltaX: 0, wheelDeltaY: 100) # goes nowhere, we're already at scrollTop 0
        Object.defineProperty(wheelEvent, 'target', get: -> lineNode)
        node.dispatchEvent(wheelEvent)

        expect(component.mouseWheelScreenRow).toBe 0
        editor.insertText("hello")
        expect(node.querySelectorAll('.line-number').length).toBe 14 # dummy line
        expect(node.querySelectorAll('.line').length).toBe 13

    describe "when the mousewheel event's target is a line number", ->
      it "keeps the line number on the DOM if it is scrolled off-screen", ->
        node.style.height = 4.5 * lineHeightInPixels + 'px'
        node.style.width = 20 * charWidth + 'px'
        component.measureScrollView()

        lineNumberNode = node.querySelectorAll('.line-number')[1]
        wheelEvent = new WheelEvent('mousewheel', wheelDeltaX: 0, wheelDeltaY: -500)
        Object.defineProperty(wheelEvent, 'target', get: -> lineNumberNode)
        node.dispatchEvent(wheelEvent)

        expect(node.contains(lineNumberNode)).toBe true

  describe "input events", ->
    inputNode = null

    beforeEach ->
      inputNode = node.querySelector('.hidden-input')

    buildTextInputEvent = ({data, target}) ->
      event = new Event('textInput')
      event.data = data
      Object.defineProperty(event, 'target', get: -> target)
      event

    it "inserts the newest character in the input's value into the buffer", ->
      node.dispatchEvent(buildTextInputEvent(data: 'x', target: inputNode))
      expect(editor.lineForBufferRow(0)).toBe 'xvar quicksort = function () {'

      node.dispatchEvent(buildTextInputEvent(data: 'y', target: inputNode))
      expect(editor.lineForBufferRow(0)).toBe 'xyvar quicksort = function () {'

    it "replaces the last character if the length of the input's value doesn't increase, as occurs with the accented character menu", ->
      node.dispatchEvent(buildTextInputEvent(data: 'u', target: inputNode))
      expect(editor.lineForBufferRow(0)).toBe 'uvar quicksort = function () {'

      # simulate the accented character suggestion's selection of the previous character
      inputNode.setSelectionRange(0, 1)
      node.dispatchEvent(buildTextInputEvent(data: 'ü', target: inputNode))
      expect(editor.lineForBufferRow(0)).toBe 'üvar quicksort = function () {'

    it "does not handle input events when input is disabled", ->
      component.setInputEnabled(false)
      node.dispatchEvent(buildTextInputEvent(data: 'x', target: inputNode))
      expect(editor.lineForBufferRow(0)).toBe 'var quicksort = function () {'

  describe "commands", ->
    describe "editor:consolidate-selections", ->
      it "consolidates selections on the editor model, aborting the key binding if there is only one selection", ->
        spyOn(editor, 'consolidateSelections').andCallThrough()

        event = new CustomEvent('editor:consolidate-selections', bubbles: true, cancelable: true)
        event.abortKeyBinding = jasmine.createSpy("event.abortKeyBinding")
        node.dispatchEvent(event)

        expect(editor.consolidateSelections).toHaveBeenCalled()
        expect(event.abortKeyBinding).toHaveBeenCalled()

  describe "hiding and showing the editor", ->
    describe "when fontSize, fontFamily, or lineHeight changes while the editor is hidden", ->
      it "does not attempt to measure the lineHeight and defaultCharWidth until the editor becomes visible again", ->
        wrapperView.hide()
        initialLineHeightInPixels = editor.getLineHeightInPixels()
        initialCharWidth = editor.getDefaultCharWidth()

        component.setLineHeight(2)
        expect(editor.getLineHeightInPixels()).toBe initialLineHeightInPixels
        expect(editor.getDefaultCharWidth()).toBe initialCharWidth
        component.setFontSize(22)
        expect(editor.getLineHeightInPixels()).toBe initialLineHeightInPixels
        expect(editor.getDefaultCharWidth()).toBe initialCharWidth
        component.setFontFamily('monospace')
        expect(editor.getLineHeightInPixels()).toBe initialLineHeightInPixels
        expect(editor.getDefaultCharWidth()).toBe initialCharWidth

        wrapperView.show()
        expect(editor.getLineHeightInPixels()).not.toBe initialLineHeightInPixels
        expect(editor.getDefaultCharWidth()).not.toBe initialCharWidth

    describe "when lines are changed while the editor is hidden", ->
      it "does not measure new characters until the editor is shown again", ->
        editor.setText('')
        wrapperView.hide()
        editor.setText('var z = 1')
        editor.setCursorBufferPosition([0, Infinity])
        wrapperView.show()
        expect(node.querySelector('.cursor').style['-webkit-transform']).toBe "translate3d(#{9 * charWidth}px, 0px, 0px)"

  buildMouseEvent = (type, properties...) ->
    properties = extend({bubbles: true, cancelable: true}, properties...)
    event = new MouseEvent(type, properties)
    Object.defineProperty(event, 'which', get: -> properties.which) if properties.which?
    if properties.target?
      Object.defineProperty(event, 'target', get: -> properties.target)
      Object.defineProperty(event, 'srcObject', get: -> properties.target)
    event
