//
//  uncialApp.swift
//  uncial
//
//  Created by Maksim Radaev on 05.09.2026.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@main
struct uncialApp: App {
    var body: some Scene {
        DocumentGroup(editing: .itemDocument, migrationPlan: uncialMigrationPlan.self) {
            ContentView()
        }
    }
}

extension UTType {
    static var itemDocument: UTType {
        UTType(importedAs: "com.example.item-document")
    }
}

struct uncialMigrationPlan: SchemaMigrationPlan {
    static var schemas: [VersionedSchema.Type] = [
        uncialVersionedSchema.self,
    ]

    static var stages: [MigrationStage] = [
        // Stages of migration between VersionedSchema, if required.
    ]
}

struct uncialVersionedSchema: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] = [
        Item.self,
    ]
}
