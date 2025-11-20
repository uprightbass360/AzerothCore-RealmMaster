package main

import (
	"image"

	ui "github.com/gizak/termui/v3"
	"github.com/gizak/termui/v3/widgets"
)

// TableNoCol is a modified table widget that doesn't draw column separators
type TableNoCol struct {
	widgets.Table
}

func NewTableNoCol() *TableNoCol {
	t := &TableNoCol{}
	t.Table = *widgets.NewTable()
	return t
}

// Draw overrides the default Draw to skip column separators
func (self *TableNoCol) Draw(buf *ui.Buffer) {
	self.Block.Draw(buf)

	if len(self.Rows) == 0 {
		return
	}

	self.ColumnResizer()

	columnWidths := self.ColumnWidths
	if len(columnWidths) == 0 {
		columnCount := len(self.Rows[0])
		columnWidth := self.Inner.Dx() / columnCount
		for i := 0; i < columnCount; i++ {
			columnWidths = append(columnWidths, columnWidth)
		}
	}

	yCoordinate := self.Inner.Min.Y

	// draw rows
	for i := 0; i < len(self.Rows) && yCoordinate < self.Inner.Max.Y; i++ {
		row := self.Rows[i]
		colXCoordinate := self.Inner.Min.X

		rowStyle := self.TextStyle
		// get the row style if one exists
		if style, ok := self.RowStyles[i]; ok {
			rowStyle = style
		}

		if self.FillRow {
			blankCell := ui.NewCell(' ', rowStyle)
			buf.Fill(blankCell, image.Rect(self.Inner.Min.X, yCoordinate, self.Inner.Max.X, yCoordinate+1))
		}

		// draw row cells
		for j := 0; j < len(row); j++ {
			col := ui.ParseStyles(row[j], rowStyle)
			// draw row cell
			if len(col) > columnWidths[j] || self.TextAlignment == ui.AlignLeft {
				for _, cx := range ui.BuildCellWithXArray(col) {
					k, cell := cx.X, cx.Cell
					if k == columnWidths[j] || colXCoordinate+k == self.Inner.Max.X {
						cell.Rune = ui.ELLIPSES
						buf.SetCell(cell, image.Pt(colXCoordinate+k-1, yCoordinate))
						break
					} else {
						buf.SetCell(cell, image.Pt(colXCoordinate+k, yCoordinate))
					}
				}
			} else if self.TextAlignment == ui.AlignCenter {
				xCoordinateOffset := (columnWidths[j] - len(col)) / 2
				stringXCoordinate := xCoordinateOffset + colXCoordinate
				for _, cx := range ui.BuildCellWithXArray(col) {
					k, cell := cx.X, cx.Cell
					buf.SetCell(cell, image.Pt(stringXCoordinate+k, yCoordinate))
				}
			} else if self.TextAlignment == ui.AlignRight {
				stringXCoordinate := ui.MinInt(colXCoordinate+columnWidths[j], self.Inner.Max.X) - len(col)
				for _, cx := range ui.BuildCellWithXArray(col) {
					k, cell := cx.X, cx.Cell
					buf.SetCell(cell, image.Pt(stringXCoordinate+k, yCoordinate))
				}
			}
			colXCoordinate += columnWidths[j] + 1
		}

		// SKIP drawing vertical separators - this is the key change

		yCoordinate++

		// draw horizontal separator
		horizontalCell := ui.NewCell(ui.HORIZONTAL_LINE, self.Block.BorderStyle)
		if self.RowSeparator && yCoordinate < self.Inner.Max.Y && i != len(self.Rows)-1 {
			buf.Fill(horizontalCell, image.Rect(self.Inner.Min.X, yCoordinate, self.Inner.Max.X, yCoordinate+1))
			yCoordinate++
		}
	}
}
