//
//  HttpParser.swift
//  Swifter
//  Copyright (c) 2015 Damian Kołakowski. All rights reserved.
//

#if os(Linux)
    import Glibc
#else
    import Foundation
#endif


enum HttpParserError : ErrorType {
    case ReadBodyFailed(String)
    case InvalidStatusLine(String)
}

class HttpParser {
    
    func readHttpRequest(socket: Socket) throws -> HttpRequest {
        let statusLine = try socket.readLine()
        print(statusLine)
        let statusLineTokens = statusLine.split(" ")
        if statusLineTokens.count < 3 {
            throw HttpParserError.InvalidStatusLine(statusLine)
        }
        let method = statusLineTokens[0]
        let path = statusLineTokens[1]
        let urlParams = extractUrlParams(path)
        let headers = try readHeaders(socket)
        if let contentLength = headers["content-length"], let contentLengthValue = Int(contentLength) {
            let body = try readBody(socket, size: contentLengthValue)
            return HttpRequest(url: path, urlParams: urlParams, method: method, headers: headers, body: body, capturedUrlGroups: [], address: nil)
        }
        return HttpRequest(url: path, urlParams: urlParams, method: method, headers: headers, body: nil, capturedUrlGroups: [], address: nil)
    }
    
    private func extractUrlParams(url: String) -> [(String, String)] {
        guard let query = url.split("?").last else {
            return []
        }
        return query.split("&").map { (param:String) -> (String, String) in
            let tokens = param.split("=")
            guard tokens.count >= 2 else {
                return ("", "")
            }
            return (tokens[0].removePercentEncoding(), tokens[1].removePercentEncoding())
        }
    }
    
    private func readBody(socket: Socket, size: Int) throws -> String {
        var body = ""
        var counter = 0;
        while counter < size {
            let c = socket.read()
            if c < 0 {
                throw HttpParserError.ReadBodyFailed(String.fromCString(UnsafePointer(strerror(errno))) ?? "Error: \(errno)")
            }
            body.append(UnicodeScalar(c))
            counter++;
        }
        return body
    }
    
    private func readHeaders(socket: Socket) throws -> [String: String] {
        var requestHeaders = [String: String]()
        repeat {
            let headerLine = try socket.readLine()
            if headerLine.isEmpty {
                return requestHeaders
            }
            let headerTokens = headerLine.split(":")
            if headerTokens.count >= 2 {
                // RFC 2616 - "Hypertext Transfer Protocol -- HTTP/1.1", paragraph 4.2, "Message Headers":
                // "Each header field consists of a name followed by a colon (":") and the field value. Field names are case-insensitive."
                // We will keep lower case version.
                let headerName = headerTokens[0].lowercaseString
                let headerValue = headerTokens[1].trim()
                if !headerName.isEmpty && !headerValue.isEmpty {
                    requestHeaders.updateValue(headerValue, forKey: headerName)
                }
            }
        } while true
    }
    
    func supportsKeepAlive(headers: [String: String]) -> Bool {
        if let value = headers["connection"] {
            return "keep-alive" == value.trim()
        }
        return false
    }
}
