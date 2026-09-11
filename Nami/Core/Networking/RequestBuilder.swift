import Foundation

struct RequestBuilder {
    var url: URL
    var method: String = "GET"
    var headers: [String: String] = [:]
    var body: Data?
    var timeout: TimeInterval = HTTPDefaults.timeout

    func build() -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.httpBody = body
        request.httpShouldHandleCookies = false
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }
}
