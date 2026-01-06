# PhotoDensityMap

A macOS app that visualizes the geographic distribution of your photo library as a smooth, continuous heatmap overlay on Apple Maps.

## Features

- **Continuous gradient heatmap** — No bubbles or markers, just a smooth color gradient showing photo density
- **Color scheme** — From blue (low density) through cyan, green, yellow, orange to red (high density)
- **Dynamic detail** — Heatmap recalculates as you zoom and pan, showing more detail at higher zoom levels
- **Adjustable intensity** — Slider to control the heat spread radius
- **Multiple map styles** — Standard, satellite, and hybrid views
- **Privacy-first** — All processing happens locally on your Mac

## Screenshot

<img width="1312" height="912" alt="image" src="https://github.com/user-attachments/assets/29cbcaf5-43c2-407d-ae31-84b4217b8217" />

## How It Works

1. Reads GPS metadata from your Photos library using PhotoKit
2. Creates a density grid using Gaussian distribution for each photo location
3. Applies Gaussian blur for smooth gradient transitions
4. Renders as a semi-transparent `MKOverlay` on MapKit

## Requirements

- macOS 14.0+
- Xcode 15+
- Photos library access permission

## Installation

1. Clone the repository
   ```bash
   git clone https://github.com/getangar/GTPhotoDensityMap.git
   ```
2. Open `GTPhotoDensityMap.xcodeproj` in Xcode
3. Set your Development Team in Signing & Capabilities
4. Build and run (⌘R)
5. Grant photo library access when prompted

## Building from Source

```bash
git clone https://github.com/getangar/GTPhotoDensityMap.git
cd GTPhotoDensityMap
open GTPhotoDensityMap.xcodeproj
```

Then build using Xcode or via command line:

```bash
xcodebuild -scheme GTPhotoDensityMap -configuration Release
```

## Privacy

PhotoDensityMap requires read-only access to your photo library to extract GPS coordinates. No data is uploaded or shared — all processing happens entirely on your device.

## License

MIT License — see [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.

## Acknowledgments

- Built with SwiftUI, MapKit, and PhotoKit
