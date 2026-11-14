import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["score", "status", "pdfButton"]
  static values = { musicxmlUrl: String, pdfFilename: String }

  async connect() {
    try {
      const response = await fetch(this.musicxmlUrlValue)
      if (!response.ok) throw new Error("Could not load this score preview.")

      const musicxml = await response.text()
      const { OpenSheetMusicDisplay } = (await import("opensheetmusicdisplay")).default
      this.display = new OpenSheetMusicDisplay(this.scoreTarget, {
        autoResize: true,
        backend: "svg"
      })
      this.musicxml = musicxml
      await this.display.load(musicxml)
      this.display.render()
      this.pdfButtonTarget.disabled = false
      this.statusTarget.textContent = "Score preview is ready."
    } catch (error) {
      this.statusTarget.textContent = error.message || "Could not render this score."
    }
  }

  async downloadPdf() {
    this.pdfButtonTarget.disabled = true
    this.statusTarget.textContent = "Preparing PDF..."

    let pdfContainer
    try {
      const [{ jsPDF }, , { default: { OpenSheetMusicDisplay } }] = await Promise.all([
        import("jspdf"),
        import("svg2pdf.js"),
        import("opensheetmusicdisplay")
      ])
      if (typeof jsPDF.API.svg !== "function") throw new Error("Could not initialize PDF export.")

      pdfContainer = document.createElement("div")
      Object.assign(pdfContainer.style, {
        position: "fixed",
        left: "-10000px",
        top: "0",
        width: "940px",
        visibility: "hidden"
      })
      document.body.appendChild(pdfContainer)

      const pdfDisplay = new OpenSheetMusicDisplay(pdfContainer, {
        autoResize: false,
        backend: "svg",
        pageFormat: "A4_P",
        newPageFromXML: true,
        newSystemFromXML: false
      })
      await pdfDisplay.load(this.musicxml)
      pdfDisplay.render()

      const svgPages = Array.from(pdfContainer.querySelectorAll("svg"))
        .filter((svg) => !svg.parentElement.closest("svg"))

      if (svgPages.length === 0) throw new Error("No rendered score pages were found.")

      let pdf
      for (const [index, svg] of svgPages.entries()) {
        const viewBox = svg.viewBox.baseVal
        if (viewBox.width <= 0 || viewBox.height <= 0) {
          throw new Error("A score page has invalid dimensions.")
        }

        const orientation = viewBox.width > viewBox.height ? "landscape" : "portrait"
        if (index === 0) {
          pdf = new jsPDF({ orientation, unit: "pt", format: "a4" })
        } else {
          pdf.addPage("a4", orientation)
        }

        const margin = 18
        await pdf.svg(svg, {
          x: margin,
          y: margin,
          width: pdf.internal.pageSize.getWidth() - margin * 2,
          height: pdf.internal.pageSize.getHeight() - margin * 2
        })
      }

      pdf.save(this.pdfFilenameValue)
      this.statusTarget.textContent = "Your PDF download is ready."
    } catch (error) {
      this.statusTarget.textContent = error.message || "Could not create the PDF."
    } finally {
      pdfContainer?.remove()
      this.pdfButtonTarget.disabled = false
    }
  }

  disconnect() {
    this.display = null
  }
}
