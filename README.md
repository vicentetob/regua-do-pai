# 🧭 The Father's Ruler (Régua do Pai)

**A free visual tool for developers to find X/Y coordinates inside PDFs and images.**  
Built with **Flutter Web** by [Tobias Vicente Flores](https://github.com/vicentetob).

🌐 [Open the Live Tool](https://reguadopai.web.app)  
📦 [View the Source Code](https://github.com/vicentetob/regua-do-pai)

---

## 🚀 Overview

The **Father's Ruler** helps developers working with libraries like  
[`pdf-lib`](https://pdf-lib.js.org/), `jsPDF`, or `PDFKit` to easily find  
exact coordinates for text, images, and shapes within PDF templates.

No more trial-and-error — just hover your mouse and copy the coordinates.

---

## ✨ Features

- 🧭 **Instant Coordinates:** Get X/Y values by simply hovering over the PDF or image.  
- 📏 **Grid & Snap Options:** Adjustable grid size and snapping for precision placement.  
- ⚙️ **JSON Export:** Save all marked points in a ready-to-use format for your code.  
- 💻 **Cross-Compatible:** Works with pdf-lib, jsPDF, PDFKit, and Flutter PDF libraries.  
- ⚡ **Runs in the Browser:** No installation, no login, just open and use.

---

## 📘 PDF Coordinate Inspector

A visual tool for inspecting and measuring coordinates on an image (screenshot of a PDF)
and obtaining their corresponding positions in the PDF coordinate system.
Perfect for mapping fields in document generation templates.

### 🧩 Overview

1. Upload a screenshot of a PDF page.
2. Adjust the target PDF dimensions (W/H) — scaling (X and Y) is auto-calculated.
3. Mark points with quick clicks (name each field), pan/zoom with drag or pinch.
4. Copy PDF coordinates, export/import JSON with all markers.
5. Configurable grid with optional snap for alignment.

### 🪄 Main Features

- Grid with main lines every 5 steps (better visibility).
- High-contrast crosshair cursor with center dot.
- Readable labels over each marker.
- Compact marker list at the bottom with copy/delete shortcuts.
- Delete individually, by right-click near a point, or via "Clear All".

### 🧭 How to Use

#### Open an Image

Click the image icon in the AppBar and select a screenshot (PNG/JPG/WebP).

#### Adjust PDF Dimensions

In the top panel, fill W and H (points) matching your PDF document.
Scale X/Y updates automatically for px → pt conversion.

#### Grid and Snap

- Enable "Grid" and adjust "Step".
- Enable "Snap" for step-multiple precision.

#### Mark Points

- Quick click (<500 ms and <10 px movement) opens "Field name" dialog.
- Drag for navigation — won't open dialog.
- You can also use the "Mark" button on the top bar.

#### Copy / Export / Import

- Each marker card has a copy icon for {x, y} in PDF coordinates.
- AppBar icons let you Export (JSON) or Import marker files.

#### Delete Markers

- Trash icon on card.
- Right-click near a point (~12 px radius).
- "Clear All" button removes all markers.

### 📐 Coordinate System & Conversion

| System | Origin | Unit |
|--------|--------|------|
| Image  | Top-left | px |
| PDF    | Bottom-left | pt |

**Scales:**
```
scaleX = pdfWidth / imageWidth
scaleY = pdfHeight / imageHeight
```

**Conversion:**
```
pdfX = imageX * scaleX
pdfY = pdfHeight - (imageY * scaleY)
```

### 🧾 Example JSON Output

```json
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
```

### 🖱️ Controls & Gestures

| Action | Description |
|--------|-------------|
| Zoom | Pinch (touchpad) or Ctrl + scroll |
| Pan | Click and drag |
| Mark | Quick click (<500 ms) |
| Remove | Right-click near marker |

---

## 🧑‍💻 Example Usage

```js
// Example using pdf-lib
page.drawText("Hello World!", {
  x: 152,
  y: 473,
});
```

---

## 🛠️ Build & Run

Requires: Flutter 3.x installed and configured.

### Web (Chrome)
```bash
flutter run -d chrome
```

### Windows Desktop
```bash
flutter config --enable-windows-desktop
flutter run -d windows
```

### Android (Optional)
```bash
flutter run -d android
```

💡 For production, run `flutter build web` and host the `build/web` folder.

---

## 🧩 Code Structure

| File | Description |
|------|-------------|
| `lib/main.dart` | Main UI and state (CoordInspectorApp, CoordHome) |
| MarkerPoint | Marker model |
| _CanvasPainter | Draws image, grid, crosshair, and markers |
| Logic | Handles JSON import/export, click vs drag, deletion, and "clear all" |

---

## 🧰 Troubleshooting

- **Bottom of PDF not visible:** Use zoom out or drag down — workspace has extra margin.
- **Dialog opens while dragging:** Only quick clicks (<500 ms and <10 px) trigger dialogs.
- **Mismatched coordinates:** Ensure PDF W/H match the real PDF dimensions (points).

---

## 🪪 License

MIT License © 2025 Tobias Vicente Flores  
Free for personal and commercial use — just credit the author.

Created with ❤️ by Tobias Vicente Flores — Sapucaia do Sul, Brazil.  
Empowering developers to build smarter tools.
