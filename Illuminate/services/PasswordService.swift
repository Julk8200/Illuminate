//
//  PasswordService.swift
//  Illuminate
//
//  Created by MrBlankCoding on 3/9/26.
//

import Foundation
import SwiftData
import SwiftUI

@MainActor
final class PasswordService {
    static let shared = PasswordService()
    
    var container: ModelContainer?
    
    private init() {}
    
    func setContainer(_ container: ModelContainer) {
        self.container = container
    }
    
    func savePassword(url: String, username: String, passwordData: String) {
        guard let context = container?.mainContext else { return }
        
        let host = URL(string: url)?.host ?? url
        
        // Check if exists
        let descriptor = FetchDescriptor<Password>(
            predicate: #Predicate<Password> { $0.url == host && $0.username == username }
        )
        
        if let existing = try? context.fetch(descriptor).first {
            existing.passwordData = passwordData
        } else {
            let newPassword = Password(url: host, username: username, passwordData: passwordData)
            context.insert(newPassword)
        }
        
        try? context.save()
    }
    
    func fetchPasswords(for url: String) -> [Password] {
        guard let context = container?.mainContext else { return [] }
        let host = URL(string: url)?.host ?? url
        
        let descriptor = FetchDescriptor<Password>(
            predicate: #Predicate<Password> { $0.url == host }
        )
        
        return (try? context.fetch(descriptor)) ?? []
    }
    
    func getAllPasswords() -> [Password] {
        guard let context = container?.mainContext else { return [] }
        let descriptor = FetchDescriptor<Password>(sortBy: [SortDescriptor(\.url)])
        return (try? context.fetch(descriptor)) ?? []
    }
}
