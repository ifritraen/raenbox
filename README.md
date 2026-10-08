# RaenBox

A premier, high-performance streaming and media application built with Flutter & Dart, supporting multiple video protocols, DASH dynamic chunk streams, Anime4K GLSL shader upscaling, multi-threaded IDM downloads, picture-in-picture, and interactive gesture controls.

## ✨ Features

- **High-Performance Player**: Powered by `media_kit` (libmpv) with hardware-accelerated video decoding (`mediacodec`), custom gesture controls, and responsive UI.
- **Anime4K Real-Time Shaders**: Integrated GLSL shaders (Modes A, B, C, A+A, B+B, C+A) and customizable color profiling.
- **Multi-Threaded Segment Downloader**: IDM-style parallel chunk worker pool for DASH and MP4 streams with sliding window memory buffering.
- **In-App MiniPlayer & PiP**: YouTube-style docked miniplayer with background floating OS Picture-in-Picture.
- **Rich Media Catalog**: Dynamic multi-region feed operating engine, trending search autocomplete, custom category manager, and backup/restore.

## 🛠️ Tech Stack

- **Framework**: Flutter (Dart SDK ^3.11.5)
- **Player & Decoders**: `media_kit`, `media_kit_video`, OpenGL shaders
- **State & Storage**: `sqflite`, `shared_preferences`
- **Networking**: `http`, custom AWS CloudFront cookie signer

## 📄 License

GPL-3.0 License.
