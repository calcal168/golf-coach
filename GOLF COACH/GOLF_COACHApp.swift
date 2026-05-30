//
//  GOLF_COACHApp.swift
//  GOLF COACH
//
//  Created by Calvin Deng on 2026-05-19.
//

import SwiftUI
import SwiftData

@main
struct GOLF_COACHApp: App {
    var sharedModelContainer: ModelContainer? = {
        let schema = GolfCoachModelContainerFactory.schema
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            GolfCoachModelContainerFactory.logContainerError(error, context: "initial")

            #if targetEnvironment(simulator)
            if GolfCoachModelContainerFactory.resetLocalStoreForSimulator() {
                do {
                    return try ModelContainer(for: schema, configurations: [modelConfiguration])
                } catch {
                    GolfCoachModelContainerFactory.logContainerError(error, context: "after simulator store reset")
                }
            }
            #endif

            do {
                let fallbackConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                return try ModelContainer(for: schema, configurations: [fallbackConfiguration])
            } catch {
                GolfCoachModelContainerFactory.logContainerError(error, context: "in-memory fallback")
                return nil
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            if let sharedModelContainer {
                ContentView()
                    .modelContainer(sharedModelContainer)
            } else {
                ModelContainerUnavailableView()
            }
        }
    }
}

enum GolfCoachModelContainerFactory {
    static let schema = Schema([
            Student.self,
            LessonPackage.self,
            LessonCharge.self,
            LessonAppointment.self,
            LessonVideo.self,
            CoachAnalysisVideo.self,
            LessonSessionNote.self,
            LessonNoteImageAttachment.self,
            Drill.self,
        ])

    static func logContainerError(_ error: Error, context: String) {
        let nsError = error as NSError
        print("SwiftData ModelContainer creation failed (\(context)).")
        print("Domain: \(nsError.domain)")
        print("Code: \(nsError.code)")
        print("Description: \(nsError.localizedDescription)")
        if !nsError.userInfo.isEmpty {
            print("UserInfo: \(nsError.userInfo)")
        }
    }

    #if targetEnvironment(simulator)
    static func resetLocalStoreForSimulator() -> Bool {
        do {
            let applicationSupportURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let storeURLs = try FileManager.default
                .contentsOfDirectory(at: applicationSupportURL, includingPropertiesForKeys: nil)
                .filter { url in
                    let fileName = url.lastPathComponent.lowercased()
                    return fileName.hasSuffix(".store") ||
                        fileName.hasSuffix(".store-shm") ||
                        fileName.hasSuffix(".store-wal") ||
                        fileName.hasSuffix(".sqlite") ||
                        fileName.hasSuffix(".sqlite-shm") ||
                        fileName.hasSuffix(".sqlite-wal")
                }

            for url in storeURLs {
                try FileManager.default.removeItem(at: url)
                print("Removed simulator SwiftData store file: \(url.path)")
            }

            return !storeURLs.isEmpty
        } catch {
            logContainerError(error, context: "simulator store reset")
            return false
        }
    }
    #endif

}

struct ModelContainerUnavailableView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Data Store Unavailable", systemImage: "externaldrive.trianglebadge.exclamationmark")
        } description: {
            Text("The app could not open its local data store. Check the Xcode console for detailed SwiftData migration errors.")
        }
    }
}
