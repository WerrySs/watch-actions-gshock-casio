# Interface principles

WatchBridge treats the selected watch as the central object rather than treating Bluetooth connectivity as the product.

- The watch image is deliberately large on the Dashboard and remains meaningful while disconnected.
- The favorite watch wins; otherwise the last connected watch is shown.
- Connection status is contextual and compact because supported watches are disconnected most of the time.
- Every screen scrolls inside the application window. Resizing never pushes navigation or actions outside the usable area.
- Action cards use two equal columns, fixed card height, a fixed heading region, and a reserved optional-value region.
- The Actions screen includes a neutral physical-button guide: A is upper-left, B upper-right, C lower-left, and D lower-right.
- Native materials are used where the platform supports them: AppKit visual effects on macOS and Mica on Windows 11.
- Status is never communicated by color alone; text, symbols, and accessible labels accompany it.

The bundled watch illustration is generic and unbranded. Product-specific photography is not fetched from manufacturer sites or third-party APIs. Users may provide their own images on macOS, where the app creates a private, metadata-free PNG copy.
