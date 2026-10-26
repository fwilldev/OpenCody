//
//  KeychainService.swift
//  OpenCody - An OpenCode Client
//
//  Created by Fabian Will on 25.02.26.
//

import Foundation
import Security

// MARK: - Errors

enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case retrieveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case dataConversionFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Keychain save failed with status: \(status)"
        case .retrieveFailed(let status):
            return "Keychain retrieve failed with status: \(status)"
        case .deleteFailed(let status):
            return "Keychain delete failed with status: \(status)"
        case .dataConversionFailed:
            return "Failed to convert keychain data to string"
        }
    }
}

// MARK: - KeychainService

struct KeychainService {
    private static let serviceName = "com.opencody.server"

    // MARK: - Save password

    /// Saves a password to the Keychain for the given identifier.
    /// If an entry already exists, it will be updated.
    static func save(password: String, for identifier: String) throws {
        guard let data = password.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: identifier,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        // Try to update an existing item first
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Item doesn't exist yet — add it
            var addQuery = query
            addQuery[kSecValueData as String] = data

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.saveFailed(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.saveFailed(updateStatus)
        }
    }

    // MARK: - Retrieve password

    /// Retrieves a password from the Keychain for the given identifier.
    /// Returns `nil` if no entry is found.
    static func retrieve(for identifier: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: identifier,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.retrieveFailed(status)
        }

        guard let data = result as? Data,
              let password = String(data: data, encoding: .utf8)
        else {
            throw KeychainError.dataConversionFailed
        }

        return password
    }

    // MARK: - Delete password

    /// Deletes a password from the Keychain for the given identifier.
    /// Does nothing if the entry does not exist.
    static func delete(for identifier: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: identifier,
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}
