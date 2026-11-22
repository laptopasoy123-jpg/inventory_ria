import { jsPDF } from 'jspdf'
import autoTable from 'jspdf-autotable'

export interface PdfSectionTable {
  title: string
  subtitle?: string
  headers: string[]
  rows: Array<Array<string | number>>
}

export interface PdfReportOptions {
  filename: string
  reportTitle: string
  periodLabel: string
  companyName?: string
  companyTagline?: string
  companyLogoDataUrl?: string | null
  summaryStats: Array<{ label: string; value: string }>
  sections: PdfSectionTable[]
}

function drawCoverBanner(
  doc: jsPDF,
  pageWidth: number,
  margin: number,
  options: PdfReportOptions,
  printedAt: string,
) {
  doc.setFillColor(11, 34, 44)
  doc.rect(0, 0, pageWidth, 26, 'F')
  doc.setFillColor(11, 125, 114)
  doc.rect(0, 26, pageWidth, 2, 'F')

  let textX = margin
  if (options.companyLogoDataUrl) {
    try {
      doc.setFillColor(255, 255, 255)
      doc.roundedRect(margin, 5, 16, 16, 2.5, 2.5, 'F')
      doc.addImage(options.companyLogoDataUrl, margin + 1.5, 6.5, 13, 13)
      textX = margin + 20
    } catch {
      textX = margin
    }
  }

  const companyName = (options.companyName || 'PT RIA INDUSTRI').toUpperCase()
  const tagline = options.companyTagline || 'INVENTRA · Divisi K3 & Pengendalian Inventaris APD'

  doc.setTextColor(255, 255, 255)
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(14)
  doc.text(companyName, textX, 11.5)

  doc.setFont('helvetica', 'normal')
  doc.setFontSize(9)
  doc.setTextColor(158, 227, 220)
  doc.text(tagline, textX, 18)

  doc.setTextColor(255, 255, 255)
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(12.5)
  doc.text(options.reportTitle, pageWidth - margin, 11.5, { align: 'right' })

  doc.setFont('helvetica', 'normal')
  doc.setFontSize(8.5)
  doc.setTextColor(203, 213, 225)
  doc.text(`Periode: ${options.periodLabel}  |  Dicetak: ${printedAt} WIB`, pageWidth - margin, 18, { align: 'right' })
}

function drawRunningHeader(doc: jsPDF, pageWidth: number, margin: number, options: PdfReportOptions) {
  const companyName = (options.companyName || 'PT RIA INDUSTRI').toUpperCase()
  doc.setFillColor(246, 250, 250)
  doc.rect(0, 0, pageWidth, 14, 'F')
  doc.setDrawColor(11, 125, 114)
  doc.setLineWidth(0.5)
  doc.line(margin, 14, pageWidth - margin, 14)

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(8.5)
  doc.setTextColor(11, 34, 44)
  doc.text(`${companyName} · INVENTRA APD`, margin, 9)

  doc.setFont('helvetica', 'normal')
  doc.setFontSize(8)
  doc.setTextColor(90, 104, 118)
  doc.text(`${options.reportTitle}  ·  Periode: ${options.periodLabel}`, pageWidth - margin, 9, { align: 'right' })
}

export function generateInventoryPdf(options: PdfReportOptions) {
  const doc = new jsPDF({ orientation: 'landscape', unit: 'mm', format: 'a4' })
  const pageWidth = doc.internal.pageSize.getWidth()
  const pageHeight = doc.internal.pageSize.getHeight()
  const margin = 14
  const printedAt = new Intl.DateTimeFormat('id-ID', {
    day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit',
  }).format(new Date())

  drawCoverBanner(doc, pageWidth, margin, options, printedAt)

  let cursorY = 34

  // Summary Boxes on Page 1
  if (options.summaryStats.length) {
    const gap = 4
    const boxW = (pageWidth - margin * 2 - gap * (options.summaryStats.length - 1)) / options.summaryStats.length
    options.summaryStats.forEach((stat, idx) => {
      const x = margin + idx * (boxW + gap)
      doc.setFillColor(244, 248, 250)
      doc.setDrawColor(218, 228, 236)
      doc.setLineWidth(0.3)
      doc.roundedRect(x, cursorY, boxW, 14, 2, 2, 'FD')

      doc.setFont('helvetica', 'normal')
      doc.setFontSize(7.5)
      doc.setTextColor(100, 116, 139)
      doc.text(stat.label.toUpperCase(), x + 3.5, cursorY + 5)

      doc.setFont('helvetica', 'bold')
      doc.setFontSize(10.5)
      doc.setTextColor(15, 23, 42)
      doc.text(stat.value, x + 3.5, cursorY + 11)
    })
    cursorY += 21
  }

  // Strictly start each new section/point on its own clean page (except the first on Page 1)
  options.sections.forEach((section, sectionIdx) => {
    if (sectionIdx > 0) {
      doc.addPage()
      cursorY = 22
    }

    doc.setFillColor(11, 125, 114)
    doc.roundedRect(margin, cursorY - 4.2, 2.6, section.subtitle ? 10 : 6.5, 0.8, 0.8, 'F')

    doc.setFont('helvetica', 'bold')
    doc.setFontSize(11.5)
    doc.setTextColor(15, 23, 42)
    doc.text(section.title, margin + 5, cursorY)

    if (section.subtitle) {
      doc.setFont('helvetica', 'normal')
      doc.setFontSize(8.5)
      doc.setTextColor(96, 112, 128)
      doc.text(section.subtitle, margin + 5, cursorY + 4.8)
      cursorY += 8.5
    } else {
      cursorY += 4.5
    }

    autoTable(doc, {
      startY: cursorY,
      margin: { top: 20, left: margin, right: margin, bottom: 18 },
      head: [section.headers],
      body: section.rows.length
        ? section.rows
        : [[{ content: 'Tidak ada data pada rentang tanggal yang dipilih.', colSpan: section.headers.length, styles: { halign: 'center', textColor: [100, 116, 139], fontStyle: 'italic' } }]],
      theme: 'grid',
      showHead: 'everyPage',
      rowPageBreak: 'avoid',
      styles: {
        font: 'helvetica',
        fontSize: 8.3,
        cellPadding: { top: 2.8, right: 3, bottom: 2.8, left: 3 },
        textColor: [30, 41, 59],
        lineColor: [222, 230, 238],
        lineWidth: 0.25,
        overflow: 'linebreak',
        valign: 'middle',
      },
      headStyles: {
        fillColor: [11, 125, 114],
        textColor: [255, 255, 255],
        fontStyle: 'bold',
        fontSize: 8.3,
        cellPadding: { top: 3.2, right: 3, bottom: 3.2, left: 3 },
      },
      alternateRowStyles: {
        fillColor: [248, 251, 252],
      },
      didParseCell(data) {
        if (data.section !== 'body') return
        const text = String(data.cell.raw ?? '').trim()
        if (/^\+\d/.test(text) || text === 'Lunas') {
          data.cell.styles.textColor = [21, 128, 61]
          data.cell.styles.fontStyle = 'bold'
        } else if (/^-\d/.test(text) || text === 'Habis') {
          data.cell.styles.textColor = [185, 28, 28]
          data.cell.styles.fontStyle = 'bold'
        } else if (text === 'Belum Dibayar' || text === 'Sebagian' || text === 'Menipis') {
          data.cell.styles.textColor = [180, 105, 12]
          data.cell.styles.fontStyle = 'bold'
        }
        if (/^[+-]?\d[\d.,]*$/.test(text)) {
          data.cell.styles.halign = 'right'
        }
      },
    })

    const lastY = (doc as unknown as { lastAutoTable?: { finalY: number } }).lastAutoTable?.finalY ?? cursorY + 12
    cursorY = lastY + 10
  })

  // Signature block on final page
  if (cursorY > pageHeight - 40) {
    doc.addPage()
    cursorY = 24
  }
  const companyLabel = options.companyName || 'PT Ria Industri'
  const sigW = (pageWidth - margin * 2 - 16) / 3
  const sigLabels = [
    'Disiapkan oleh,\nAdmin Gudang APD',
    'Diperiksa oleh,\nSafety Inspector (K3)',
    `Disetujui oleh,\nManajemen ${companyLabel}`,
  ]
  sigLabels.forEach((lbl, idx) => {
    const x = margin + idx * (sigW + 8)
    doc.setDrawColor(203, 213, 225)
    doc.setLineWidth(0.3)
    doc.roundedRect(x, cursorY, sigW, 22, 2, 2, 'S')
    const [top, bottom] = lbl.split('\n')
    doc.setFont('helvetica', 'normal')
    doc.setFontSize(8)
    doc.setTextColor(100, 116, 139)
    doc.text(top || '', x + sigW / 2, cursorY + 5.5, { align: 'center' })
    doc.setFont('helvetica', 'bold')
    doc.setFontSize(8.5)
    doc.setTextColor(15, 23, 42)
    doc.text(bottom || '', x + sigW / 2, cursorY + 19, { align: 'center' })
  })

  const totalPages = doc.getNumberOfPages()
  const year = new Date().getFullYear()
  for (let p = 1; p <= totalPages; p++) {
    doc.setPage(p)
    if (p > 1) {
      drawRunningHeader(doc, pageWidth, margin, options)
    }
    doc.setDrawColor(222, 230, 238)
    doc.setLineWidth(0.3)
    doc.line(margin, pageHeight - 12, pageWidth - margin, pageHeight - 12)
    doc.setFont('helvetica', 'normal')
    doc.setFontSize(8)
    doc.setTextColor(71, 85, 105)
    doc.text(`Copyright © ${year} by DaySheet.id · INVENTRA APD Asset Control (${companyLabel})`, margin, pageHeight - 7)
    doc.text(`Halaman ${p} dari ${totalPages}`, pageWidth - margin, pageHeight - 7, { align: 'right' })
  }

  doc.save(options.filename)
}
