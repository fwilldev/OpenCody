import Foundation

// MARK: - MultipartFormData

/// Builds multipart/form-data request bodies for file uploads.
struct MultipartFormData: Sendable {
    let boundary: String
    private var parts: [Part] = []

    init(boundary: String = UUID().uuidString) {
        self.boundary = boundary
    }

    // MARK: - Adding Parts

    /// Append a plain text field.
    mutating func append(name: String, value: String) {
        let data = Data(value.utf8)
        parts.append(Part(name: name, filename: nil, mimeType: "text/plain", data: data))
    }

    /// Append a file part with explicit MIME type.
    mutating func append(name: String, filename: String, mimeType: String, data: Data) {
        parts.append(Part(name: name, filename: filename, mimeType: mimeType, data: data))
    }

    // MARK: - Build Body

    /// Assembles all parts into the final multipart body `Data`.
    func buildBody() -> Data {
        var body = Data()
        let boundaryPrefix = "--\(boundary)\r\n"

        for part in parts {
            body.append(Data(boundaryPrefix.utf8))

            if let filename = part.filename {
                body.append(Data(
                    "Content-Disposition: form-data; name=\"\(part.name)\"; filename=\"\(filename)\"\r\n"
                        .utf8
                ))
            } else {
                body.append(Data(
                    "Content-Disposition: form-data; name=\"\(part.name)\"\r\n".utf8
                ))
            }

            body.append(Data("Content-Type: \(part.mimeType)\r\n\r\n".utf8))
            body.append(part.data)
            body.append(Data("\r\n".utf8))
        }

        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }

    // MARK: - APIEndpoint Integration

    /// Creates an `APIEndpoint` configured for multipart upload.
    func endpoint(path: String) -> APIEndpoint {
        APIEndpoint(
            path: path,
            method: .POST,
            body: buildBody(),
            contentType: .multipart(boundary: boundary)
        )
    }

    // MARK: - Private

    private struct Part: Sendable {
        let name: String
        let filename: String?
        let mimeType: String
        let data: Data
    }
}
