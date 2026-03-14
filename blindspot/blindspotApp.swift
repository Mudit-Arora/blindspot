//
//  blindspotApp.swift
//  blindspot
//
//  Created by Mudit Arora on 3/14/26.
//

import SwiftUI
import CoreData

@main
struct blindspotApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
