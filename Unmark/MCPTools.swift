import AppKit
import ImageIO
import UniformTypeIdentifiers

@MainActor
enum MCPTools {
    private static let identifier: [String: Any] = ["type": "string", "description": "Image ID returned by import_images or list_images."]
    private static let rectangle: [String: Any] = [
        "type": "object", "description": "Normalized top-left rectangle. All values are 0–1; leave a margin from image edges.",
        "properties": Dictionary(uniqueKeysWithValues: ["x", "y", "width", "height"].map {
            ($0, ["type": "number", "minimum": 0, "maximum": 1] as [String: Any])
        }), "required": ["x", "y", "width", "height"], "additionalProperties": false
    ]

    static let catalog: [[String: Any]] = [
        tool("list_images", "List images in the active Unmark window, IDs, pixel dimensions, edit counts and processing status.", [:], [], readOnly: true),
        tool("import_images", "Open local still images in Unmark. Absolute paths inside your home folder; up to 20 per call, 10 MB each. Existing images keep their edits.",
             ["paths": ["type": "array", "items": ["type": "string"], "minItems": 1, "maxItems": 20]], ["paths"]),
        tool("clean_image", "Remove a small mark using surrounding pixels. Small/large target the bottom-right sparkle preset; custom requires a rectangle. Edits accumulate. Does not recover hidden details. Runs locally and can be cancelled.",
             ["image_id": identifier, "mode": ["type": "string", "enum": ["small", "large", "custom"]], "region": rectangle], ["image_id", "mode"]),
        tool("preview_image", "Return an image preview (PNG, longest side at most 1024 pixels) for visual inspection. Coordinates for clean_image refer to this oriented image, with top-left origin.",
             ["image_id": identifier, "original": ["type": "boolean", "default": false]], ["image_id"], readOnly: true),
        tool("export_image", "Save a cleaned image to an absolute path in your home folder. Never overwrites a file or an imported original. Destination extension must match the chosen output format.",
             ["image_id": identifier, "destination": ["type": "string"], "format": ["type": "string", "enum": ["png", "original"]]], ["image_id", "destination"]),
        tool("reset_image", "Discard all edits for one image and return to its original. Exported files are kept.", ["image_id": identifier], ["image_id"]),
        tool("check_tools", "Check the locally installed FFmpeg and FFprobe, including delogo support. Installs nothing.", [:], [], readOnly: true),
        tool("cancel_operation", "Cancel the active window's current cleanup, export or tool check. Previously completed edits and exports are kept.", [:], [])
    ]

    static var names: Set<String> { Set(catalog.compactMap { $0["name"] as? String }) }

    private static func tool(_ name: String, _ description: String, _ properties: [String: Any], _ required: [String], readOnly: Bool = false) -> [String: Any] {
        ["name": name, "description": description,
         "inputSchema": ["type": "object", "properties": properties, "required": required, "additionalProperties": false],
         "annotations": ["readOnlyHint": readOnly, "destructiveHint": name == "reset_image", "openWorldHint": false]]
    }

    static func failure(_ message: String) -> [String: Any] {
        ["content": [["type": "text", "text": message]], "isError": true]
    }

    private static func success(_ value: [String: Any]) -> [String: Any] {
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data()
        return ["content": [["type": "text", "text": String(decoding: data, as: UTF8.self)]], "structuredContent": value, "isError": false]
    }

    static func validate(_ name: String, _ arguments: [String: Any]) throws {
        guard let schema = catalog.first(where: { $0["name"] as? String == name })?["inputSchema"] as? [String: Any],
              let properties = schema["properties"] as? [String: Any], let required = schema["required"] as? [String],
              Set(arguments.keys).isSubset(of: Set(properties.keys)), required.allSatisfy({ arguments[$0] != nil }) else {
            throw CleanupFailure(message: "Missing or unknown tool arguments. Check tools/list for the schema.")
        }
        for key in ["image_id", "mode", "destination", "format"] where arguments[key] != nil {
            guard let value = arguments[key] as? String, !value.isEmpty, value.utf8.count <= 4096 else {
                throw CleanupFailure(message: "\(key) must be a nonempty string.")
            }
        }
        if let original = arguments["original"], CFGetTypeID(original as CFTypeRef) != CFBooleanGetTypeID() {
            throw CleanupFailure(message: "original must be true or false.")
        }
        if let mode = arguments["mode"] as? String, !["small", "large", "custom"].contains(mode) {
            throw CleanupFailure(message: "mode must be small, large or custom.")
        }
        if let format = arguments["format"] as? String, !["png", "original"].contains(format) {
            throw CleanupFailure(message: "format must be png or original.")
        }
        if arguments["region"] != nil { _ = try region(arguments["region"]) }
        if arguments["mode"] as? String == "custom", arguments["region"] == nil {
            throw CleanupFailure(message: "Custom cleanup requires region: {x, y, width, height}.")
        }
    }

    private static func region(_ raw: Any?) throws -> CGRect {
        guard let values = raw as? [String: Any], Set(values.keys) == Set(["x", "y", "width", "height"]) else {
            throw CleanupFailure(message: "region requires x, y, width and height.")
        }
        var numbers: [String: Double] = [:]
        for (key, raw) in values {
            guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
                  value.doubleValue.isFinite, (0...1).contains(value.doubleValue) else {
                throw CleanupFailure(message: "Rectangle values must be numbers between 0 and 1.")
            }
            numbers[key] = value.doubleValue
        }
        let rect = CGRect(x: numbers["x"]!, y: numbers["y"]!, width: numbers["width"]!, height: numbers["height"]!)
        guard rect.width > 0, rect.height > 0, rect.maxX <= 1, rect.maxY <= 1 else {
            throw CleanupFailure(message: "The rectangle must fit inside the image and have a positive size.")
        }
        return rect
    }

    private static func file(_ path: String) throws -> URL {
        guard path.hasPrefix("/"), !path.contains("\0"), path.utf8.count <= 4096 else {
            throw CleanupFailure(message: "Use an absolute local file path.")
        }
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.resolvingSymlinksInPath().path
        guard url.path.hasPrefix(home + "/") else {
            throw CleanupFailure(message: "AI access is limited to files inside your home folder, including resolved symbolic links.")
        }
        return url
    }

    private static func item(_ arguments: [String: Any], in workspace: Workspace) throws -> ImageItem {
        guard let raw = arguments["image_id"] as? String, let id = UUID(uuidString: raw),
              let item = workspace.items.first(where: { $0.id == id }) else {
            throw CleanupFailure(message: "Image not found. Call list_images to get its current ID.")
        }
        return item
    }

    private static func describe(_ item: ImageItem) -> [String: Any] {
        let size = item.image.representations.first
        return ["image_id": item.id.uuidString, "path": item.source.path, "width": size?.pixelsWide ?? 0,
                "height": size?.pixelsHigh ?? 0, "mode": item.mode.lowercased(), "edits": item.editCount,
                "cleaned": item.result != nil, "status": item.status]
    }

    static func call(_ name: String, _ arguments: [String: Any], workspace: Workspace) async throws -> [String: Any] {
        switch name {
        case "list_images":
            return success(["images": workspace.items.map(describe), "busy": workspace.busy || workspace.testing, "activity": workspace.activity])
        case "import_images":
            try workspace.requireAIIdle()
            guard let paths = arguments["paths"] as? [String], (1...20).contains(paths.count), workspace.items.count + paths.count <= 100 else {
                throw CleanupFailure(message: "Import 1–20 images at a time, with at most 100 images in the window.")
            }
            let urls = try paths.map(file)
            // Validate every path before changing the editor.
            for url in urls { try ImageFormats.validateImport(url) }
            workspace.error = nil
            workspace.add(urls)
            if let error = workspace.error { workspace.error = nil; throw CleanupFailure(message: error) }
            return success(["images": workspace.items.filter { urls.contains($0.source) }.map(describe)])
        case "clean_image":
            let image = try item(arguments, in: workspace)
            let mode = (arguments["mode"] as? String ?? "small").capitalized
            let selectedRegion = mode == "Custom" ? try region(arguments["region"]) : nil
            let updated = try await workspace.cleanForAI(image.id, mode: mode, region: selectedRegion)
            return success(describe(updated))
        case "preview_image":
            let image = try item(arguments, in: workspace)
            let original = arguments["original"] as? Bool ?? false
            let input = original ? image.source : (image.result ?? image.source)
            if input == image.source { try ImageFormats.validateImport(input) }
            let data = try await MCPPreview.shared.make(input)
            return ["content": [["type": "text", "text": "\(image.source.lastPathComponent) — \(original ? "original" : "current result"). Rectangle coordinates use the top-left origin."],
                                ["type": "image", "mimeType": "image/png", "data": data.base64EncodedString()]], "isError": false]
        case "export_image":
            let image = try item(arguments, in: workspace)
            let destination = try file(arguments["destination"] as? String ?? "")
            let receipt = try await workspace.exportForAI(image.id, destination: destination, preference: arguments["format"] as? String)
            return success(["files": receipt.files.map(\.path), "notes": receipt.notes])
        case "reset_image":
            try workspace.requireAIIdle()
            let image = try item(arguments, in: workspace)
            workspace.selectedID = image.id; workspace.resetEdits()
            return success(describe(try item(arguments, in: workspace)))
        case "check_tools":
            try workspace.requireAIIdle()
            let report = try await workspace.checkToolsForAI()
            return success(["ready": report.ready, "message": report.message, "ffmpeg": report.ffmpeg ?? "", "ffprobe": report.ffprobe ?? ""])
        case "cancel_operation":
            let running = workspace.busy || workspace.testing
            workspace.cancelOperation()
            return success(["cancellation_requested": running])
        default: throw CleanupFailure(message: "Unknown tool.")
        }
    }
}

actor MCPPreview {
    static let shared = MCPPreview()
    func make(_ input: URL) throws -> Data {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024
              ] as CFDictionary) else { throw CleanupFailure(message: "Could not create an image preview.") }
        let data = NSMutableData()
        guard let output = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CleanupFailure(message: "Could not encode the preview.")
        }
        CGImageDestinationAddImage(output, image, nil)
        guard CGImageDestinationFinalize(output) else { throw CleanupFailure(message: "Could not finish the preview.") }
        return data as Data
    }
}
