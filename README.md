# 🧭 The Father's Ruler (Régua do Pai)

[![Firebase Hosting](https://img.shields.io/badge/hosting-firebase-orange?logo=firebase)](https://regua-do-pai.web.app)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Made with Flutter](https://img.shields.io/badge/Made%20with-Flutter-blue?logo=flutter)](https://flutter.dev)
[![Open Source](https://img.shields.io/badge/Open%20Source-💚-brightgreen)](https://github.com/vicentetob/regua-do-pai)

**A free visual tool for developers to find X/Y coordinates inside PDFs and images.**  
Built with **Flutter Web** by [Tobias Vicente Flores](https://github.com/vicentetob) — founder of [GreenWatt Renováveis](https://gw.solar).

🌐 [Open the Live Tool](https://regua-do-pai.web.app)  
📦 [View the Source Code](https://github.com/vicentetob/regua-do-pai)

---

## 🚀 Overview

The **Father's Ruler** helps developers working with libraries like  
[`pdf-lib`](https://pdf-lib.js.org/), [`jsPDF`](https://github.com/parallax/jsPDF), or [`PDFKit`](https://pdfkit.org/)  
to easily find exact coordinates for text, images, and shapes within PDF templates.

No more trial-and-error — just hover your mouse and copy the coordinates.  
Created as a developer productivity tool and shared freely with the community.

---

## ✨ Features

- 🧭 **Instant Coordinates:** Get X/Y values by hovering over the PDF or image.  
- 📏 **Grid & Snap Options:** Adjustable grid size and snapping for precision.  
- ⚙️ **JSON Export:** Save all marked points in a ready-to-use format for your code.  
- 💻 **Cross-Compatible:** Works with pdf-lib, jsPDF, PDFKit, and Flutter PDF libraries.  
- ⚡ **Runs in the Browser:** No installation, no login, just open and use.  
- 🧩 **Multi-Platform:** Works on mobile, tablet, and desktop browsers.

---

## 📘 PDF Coordinate Inspector

A visual inspector to find coordinates on screenshots of PDFs and map them to their equivalent PDF coordinates.  
Perfect for positioning text fields or images dynamically in document-generation templates.

### 🧩 Overview

1. Upload a screenshot of a PDF page.  
2. Adjust the target PDF dimensions (W/H) — scales auto-calculate.  
3. Mark points and name fields with quick clicks.  
4. Copy or export coordinates to JSON.  
5. Import JSON to restore markers anytime.

---

## 🪄 Main Features

- Grid with adjustable spacing and optional snapping.  
- Crosshair cursor with central dot and live coordinate display.  
- Named markers with color-coded dots and label overlays.  
- Compact marker list with copy/delete shortcuts.  
- Support for right-click delete and full "Clear All" wipe.  
- Real-time px ↔ pt coordinate conversion (image vs. PDF).

---

## 🧭 How to Use

#### 1️⃣ Open an Image
Click the “Open Image” icon and select a screenshot of your PDF (PNG/JPG/WebP).

#### 2️⃣ Adjust PDF Dimensions
In the left panel, fill the PDF Width and Height (in points).  
The scale factors for X/Y are automatically recalculated.

#### 3️⃣ Use the Grid
Enable “Show Grid” and adjust “Step” for spacing.  
Activate “Snap to Grid” for precision alignment.

#### 4️⃣ Mark Points
Quick click → opens dialog to name the field.  
Drag for panning (does not create markers).

#### 5️⃣ Copy / Export / Import
Export JSON of all markers, or import back to restore.

---

## 📐 Coordinate System & Conversion

| System | Origin | Unit |
|--------|--------|------|
| Image  | Top-left | px |
| PDF    | Bottom-left | pt |

**Scale Calculation**
```text
scaleX = pdfWidth / imageWidth
scaleY = pdfHeight / imageHeight
Conversion

text
Copiar código
pdfX = imageX * scaleX
pdfY = pdfHeight - (imageY * scaleY)
🧾 Example JSON Output
json
Copiar código
{
  "meta": {
    "imageWidth": 1654,
    "imageHeight": 2339,
    "pdfWidth": 1654,
    "pdfHeight": 2339,
    "origin": "bottomLeft",
    "scaleX": 1.0,
    "scaleY": 1.0
  },
  "markers": {
    "field_1": {
      "image": { "x": 838.3, "y": 173.9 },
      "pdf":   { "x": 838.3, "y": 2165.1 }
    }
  }
}
🖱️ Controls & Gestures
Action	Description
Zoom	Pinch or Ctrl + Scroll
Pan	Click and Drag
Mark	Quick Click (<500ms)
Remove	Right-click near marker
Clear All	Deletes all markers

🧑‍💻 Example Usage (pdf-lib)
js
Copiar código
import { PDFDocument, StandardFonts, rgb } from 'pdf-lib';

const pdfDoc = await PDFDocument.create();
const page = pdfDoc.addPage();
page.drawText("Hello World!", {
  x: 152,
  y: 473,
});
🛠️ Build & Run
Requires: Flutter 3.x configured and updated.

Web (Recommended)
bash
Copiar código
flutter build web --release
firebase deploy --only hosting
Windows
bash
Copiar código
flutter config --enable-windows-desktop
flutter run -d windows
Android
bash
Copiar código
flutter run -d android
🧩 Code Structure
File	Description
lib/main.dart	Main UI logic (CoordInspectorApp, CoordHome)
MarkerPoint	Marker model with px ↔ pt conversion
_CanvasPainter	Handles drawing grid, crosshair, and markers
Logic	Import/export JSON, click vs drag detection, delete, etc.

🧰 Troubleshooting
PDF bottom hidden: Use zoom-out or drag the view.

Dialog opens on drag: Only short clicks (<500ms & <10px) create markers.

Wrong coordinates: Ensure the entered PDF width/height matches the actual document.

Grid not visible: Try resetting grid size to 10px.

💡 About the Project
The Régua do Pai was created by Tobias Vicente Flores, founder of GreenWatt Renováveis,
as part of the Papai Solar Ecosystem — tools designed to empower engineers, technicians,
and creators with intelligent, open-source technology.

It embodies the philosophy that knowledge and progress should be shared,
so everyone can build better tools, faster, and with purpose. ⚡

🪪 License
MIT License © 2025 Tobias Vicente Flores
Free for personal and commercial use — just credit the author.

Created with ❤️ by Tobias Vicente Flores — Sapucaia do Sul, Brazil.
Empowering developers to build smarter tools.
