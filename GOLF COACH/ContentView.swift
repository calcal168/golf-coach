//
//  ContentView.swift
//  GOLF COACH
//
//  Created by Calvin Deng on 2026-05-19.
//

import EventKit
import EventKitUI
import MessageUI
import CoreTransferable
import PhotosUI
import Photos
import AVKit
import AVFoundation
import LocalAuthentication
import Observation
import ReplayKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import UIKit

private enum AppLanguage: String, CaseIterable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case korean = "ko"

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    var displayName: LocalizedStringKey {
        switch self {
        case .english:
            return "English"
        case .simplifiedChinese:
            return "Simplified Chinese"
        case .traditionalChinese:
            return "Traditional Chinese"
        case .korean:
            return "Korean"
        }
    }
}

enum AppTab: String, Codable {
    case students
    case schedule
    case payments
    case videos
    case drills
}

struct LastSessionState: Codable, Equatable {
    var selectedTab: AppTab = .students
    var selectedStudentID: Data?
    var selectedStudentName: String?
    var selectedLessonDate: Date?
    var beforeComparisonVideoID: Data?
    var afterComparisonVideoID: Data?
    var playbackSpeed: Float = 1.0
    var beforeVideoProgress = 0.0
    var afterVideoProgress = 0.0

    var hasActiveCoachingSession: Bool {
        selectedStudentID != nil && selectedLessonDate != nil
    }

    var hasComparison: Bool {
        beforeComparisonVideoID != nil && afterComparisonVideoID != nil
    }
}

@MainActor
@Observable
final class SessionStateManager {
    private static let storageKey = "lastSessionState"

    private(set) var state: LastSessionState

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let restored = try? JSONDecoder().decode(LastSessionState.self, from: data) {
            state = restored
        } else {
            state = LastSessionState()
        }
    }

    func setSelectedTab(_ tab: AppTab) {
        state.selectedTab = tab
        save()
    }

    func selectStudent(_ student: Student, preservingDetail: Bool = false) {
        state.selectedStudentID = identifierData(for: student)
        state.selectedStudentName = student.name
        if !preservingDetail {
            state.selectedLessonDate = nil
            clearComparison()
        }
        save()
    }

    func selectLessonDate(_ date: Date, preservingComparison: Bool = false) {
        state.selectedLessonDate = Calendar.current.startOfDay(for: date)
        if !preservingComparison {
            clearComparison()
        }
        save()
    }

    func updateComparison(
        beforeVideo: LessonVideo,
        afterVideo: LessonVideo,
        playbackSpeed: Float,
        beforeProgress: Double,
        afterProgress: Double
    ) {
        state.beforeComparisonVideoID = identifierData(for: beforeVideo)
        state.afterComparisonVideoID = identifierData(for: afterVideo)
        state.playbackSpeed = playbackSpeed
        state.beforeVideoProgress = beforeProgress
        state.afterVideoProgress = afterProgress
        save()
    }

    func startFresh() {
        let selectedTab = state.selectedTab
        state = LastSessionState(selectedTab: selectedTab)
        save()
    }

    func matches<Model: PersistentModel>(_ model: Model, storedIdentifier: Data?) -> Bool {
        guard let storedIdentifier,
              let identifier = try? JSONDecoder().decode(PersistentIdentifier.self, from: storedIdentifier) else {
            return false
        }
        return model.persistentModelID == identifier
    }

    private func identifierData<Model: PersistentModel>(for model: Model) -> Data? {
        try? JSONEncoder().encode(model.persistentModelID)
    }

    private func clearComparison() {
        state.beforeComparisonVideoID = nil
        state.afterComparisonVideoID = nil
        state.playbackSpeed = 1.0
        state.beforeVideoProgress = 0
        state.afterVideoProgress = 0
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("selectedAppLanguage") private var selectedAppLanguage = AppLanguage.english.rawValue
    @AppStorage("prefersDarkMode") private var prefersDarkMode = false
    @Query(sort: \Student.name) private var students: [Student]
    @State private var sessionStateManager = SessionStateManager()
    @State private var selectedTab: AppTab = .students
    @State private var requestedRestoration: LastSessionState?
    @State private var selectedVideo: VideoPlaybackSelection?
    @State private var selectedCoachAnalysis: CoachAnalysisPlaybackSelection?
    @State private var isPreparingVideo = false
    @State private var isPreparingCoachAnalysis = false
    @State private var isUnlocked = false
    @State private var isAuthenticating = false
    @State private var authenticationMessage: String?

    var body: some View {
        Group {
            if isUnlocked {
                applicationContent
            } else {
                AppLockView(
                    isAuthenticating: isAuthenticating,
                    message: authenticationMessage,
                    onUnlock: authenticate
                )
            }
        }
        .task {
            selectedTab = sessionStateManager.state.selectedTab
            authenticate()
        }
        .onChange(of: isUnlocked) { _, unlocked in
            guard unlocked else { return }
            prepareSessionRestoration()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                authenticate()
            case .background:
                lockApp()
            case .inactive:
                break
            @unknown default:
                lockApp()
            }
        }
        .environment(
            \.locale,
            AppLanguage(rawValue: selectedAppLanguage)?.locale ?? AppLanguage.english.locale
        )
        .preferredColorScheme(prefersDarkMode ? .dark : .light)
    }

    private var applicationContent: some View {
        TabView(selection: $selectedTab) {
            StudentDirectoryView(
                onPlayVideo: openVideo,
                onPlayCoachAnalysis: openCoachAnalysis,
                sessionStateManager: sessionStateManager,
                restorationRequest: $requestedRestoration
            )
                .tabItem { Label("Students", systemImage: "person.2") }
                .tag(AppTab.students)

            ScheduleView()
                .tabItem { Label("Schedule", systemImage: "calendar") }
                .tag(AppTab.schedule)

            PaymentsView()
                .tabItem { Label("Payments", systemImage: "creditcard") }
                .tag(AppTab.payments)

            VideoLibraryView(onPlayVideo: openVideo)
                .tabItem { Label("Videos", systemImage: "video") }
                .tag(AppTab.videos)

            DrillLibraryView()
                .tabItem { Label("Drills", systemImage: "list.bullet.clipboard") }
                .tag(AppTab.drills)
        }
        .onChange(of: selectedTab) { _, tab in
            sessionStateManager.setSelectedTab(tab)
        }
        .fullScreenCover(item: $selectedVideo, onDismiss: {
            print("DEBUG ContentView selectedVideo cleared on dismiss")
            selectedVideo = nil
            isPreparingVideo = false
        }) { selection in
            VideoPlayerSheet(video: selection.video, studentName: selection.studentName, student: selection.student)
        }
        .fullScreenCover(item: $selectedCoachAnalysis, onDismiss: {
            print("DEBUG ContentView selectedCoachAnalysis cleared on dismiss")
            selectedCoachAnalysis = nil
            isPreparingCoachAnalysis = false
        }) { selection in
            CoachAnalysisView(analysis: selection.analysis)
        }
    }

    private func authenticate() {
        guard !isUnlocked, !isAuthenticating, scenePhase == .active else { return }

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var authenticationError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authenticationError) else {
            authenticationMessage = "Set a passcode on this device to protect student information."
            return
        }

        isAuthenticating = true
        authenticationMessage = nil

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock Golf Coach to view student information."
        ) { success, error in
            Task { @MainActor in
                isAuthenticating = false

                if success, scenePhase == .active {
                    isUnlocked = true
                    authenticationMessage = nil
                } else if success {
                    isUnlocked = false
                } else if let error = error as? LAError, error.code == .userCancel {
                    authenticationMessage = nil
                } else {
                    authenticationMessage = "Authentication failed. Try again to open the app."
                }
            }
        }
    }

    private func lockApp() {
        isUnlocked = false
        authenticationMessage = nil
        selectedVideo = nil
        selectedCoachAnalysis = nil
        isPreparingVideo = false
        isPreparingCoachAnalysis = false
    }

    private func prepareSessionRestoration() {
        let savedState = sessionStateManager.state
        guard students.contains(where: {
            sessionStateManager.matches($0, storedIdentifier: savedState.selectedStudentID)
        }) else {
            if savedState.selectedStudentID != nil {
                sessionStateManager.startFresh()
            }
            return
        }

        if savedState.hasActiveCoachingSession {
            selectedTab = .students
            sessionStateManager.setSelectedTab(.students)
            requestedRestoration = savedState
        } else {
            requestedRestoration = savedState
        }
    }

    private func openVideo(_ video: LessonVideo, student: Student) {
        guard selectedVideo == nil, !isPreparingVideo, video.fileURL != nil else {
            print("DEBUG ContentView selectedVideo ignored duplicate tap: \(video.title)")
            return
        }

        isPreparingVideo = true
        selectedVideo = VideoPlaybackSelection(video: video, studentName: student.name, student: student)
        print("DEBUG ContentView selectedVideo set: \(video.title)")
        isPreparingVideo = false
    }

    private func openCoachAnalysis(_ analysis: CoachAnalysisVideo) {
        guard selectedCoachAnalysis == nil, !isPreparingCoachAnalysis else {
            print("DEBUG ContentView selectedCoachAnalysis ignored duplicate tap: \(analysis.title)")
            return
        }

        isPreparingCoachAnalysis = true
        selectedCoachAnalysis = CoachAnalysisPlaybackSelection(analysis: analysis)
        print("DEBUG ContentView selectedCoachAnalysis set: \(analysis.title)")
        isPreparingCoachAnalysis = false
    }
}

private struct AppLockView: View {
    let isAuthenticating: Bool
    let message: String?
    let onUnlock: () -> Void

    var body: some View {
        ZStack {
            StudentDirectoryPalette.pageBackground
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(StudentDirectoryPalette.primary)
                    .frame(width: 72, height: 72)
                    .background(StudentDirectoryPalette.iconBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(spacing: 8) {
                    Text("Golf Coach Locked")
                        .font(.title3.weight(.semibold))

                    Text("Authenticate to access student information.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }

                Button(action: onUnlock) {
                    Label {
                        if isAuthenticating {
                            Text("Authenticating...")
                        } else {
                            Text("Unlock App")
                        }
                    } icon: {
                        Image(systemName: isAuthenticating ? "faceid" : "lock.open.fill")
                    }
                    .font(.headline)
                    .frame(maxWidth: 240)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(StudentDirectoryPalette.primary)
                .disabled(isAuthenticating)
            }
            .padding(28)
        }
    }
}

private struct GolfCoachNavigationTitle: View {
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(StudentDirectoryPalette.brandGreen)

                Image(systemName: "flag.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .offset(x: 1, y: -2)

                Circle()
                    .fill(StudentDirectoryPalette.brandGold)
                    .frame(width: 6, height: 6)
                    .offset(x: -8, y: 11)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 0) {
                Text("GOLF COACH")
                    .font(.system(size: 18, weight: .bold, design: .default))
                    .foregroundStyle(StudentDirectoryPalette.brandGreen)

                Text("Academy")
                    .font(.system(size: 10, weight: .semibold, design: .default))
                    .foregroundStyle(StudentDirectoryPalette.brandGold)
                    .textCase(.uppercase)
            }
        }
        .minimumScaleFactor(0.82)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Golf Coach Academy")
    }
}

struct StudentDirectoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("selectedAppLanguage") private var selectedAppLanguage = AppLanguage.english.rawValue
    @AppStorage("prefersDarkMode") private var prefersDarkMode = false
    @Query(sort: \Student.name) private var students: [Student]
    let onPlayVideo: (LessonVideo, Student) -> Void
    let onPlayCoachAnalysis: (CoachAnalysisVideo) -> Void
    let sessionStateManager: SessionStateManager
    @Binding var restorationRequest: LastSessionState?
    @State private var isExportingStudents = false
    @State private var navigationPath: [Student] = []
    @State private var highlightedStudentID: PersistentIdentifier?
    @State private var selectedStudentPrompt: String?
    @State private var searchText = ""
    @State private var studentsPendingDeletion: [Student] = []
    @State private var isConfirmingStudentDeletion = false
    @State private var backupDocument: GolfCoachBackupDocument?
    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var backupPendingRestore: GolfCoachBackupSnapshot?
    @State private var isConfirmingBackupRestore = false
    @State private var backupStatusTitle = ""
    @State private var backupStatusMessage = ""
    @State private var isShowingBackupStatus = false
    @State private var hasAutomaticBackup = false
    @State private var isComposingMarketingEmail = false

    private var filteredStudents: [Student] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return students }

        return students.filter { student in
            student.name.localizedCaseInsensitiveContains(query)
        }
    }

    private var marketingEmailRecipients: [String] {
        Array(
            Set(
                students
                    .map { $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted()
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                if students.isEmpty {
                    StudentDirectoryEmptyState()
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    StudentDirectoryOverview(students: filteredStudents, totalStudentCount: students.count)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    if filteredStudents.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(filteredStudents) { student in
                            Button {
                                openStudent(student)
                            } label: {
                                StudentRow(
                                    student: student,
                                    isHighlighted: highlightedStudentID == student.persistentModelID
                                )
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        .onDelete(perform: stageStudentsForDeletion)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(StudentDirectoryPalette.pageBackground)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search students")
            .overlay(alignment: .top) {
                if let selectedStudentPrompt {
                    StudentSelectionPrompt(studentName: selectedStudentPrompt)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                        .padding(.top, 12)
                }
            }
            .navigationDestination(for: Student.self) { student in
                StudentDetailView(
                    student: student,
                    onPlayVideo: onPlayVideo,
                    onPlayCoachAnalysis: onPlayCoachAnalysis,
                    sessionStateManager: sessionStateManager,
                    restoredSession: restoredSession(for: student),
                    onRestorationHandled: { restorationRequest = nil }
                )
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    GolfCoachNavigationTitle()
                }

                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Menu {
                            ForEach(AppLanguage.allCases, id: \.self) { language in
                                Button {
                                    selectedAppLanguage = language.rawValue
                                } label: {
                                    if selectedAppLanguage == language.rawValue {
                                        Label(language.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(language.displayName)
                                    }
                                }
                            }
                        } label: {
                            Label("Language", systemImage: "globe")
                        }

                        Divider()

                        Button {
                            isExportingStudents = true
                        } label: {
                            Label("Export Spreadsheet", systemImage: "tablecells")
                        }
                        .disabled(students.isEmpty)

                        Divider()

                        Button {
                            createBackup()
                        } label: {
                            Label("Back Up Student Data", systemImage: "externaldrive.badge.plus")
                        }
                        .disabled(students.isEmpty)

                        Button {
                            isImportingBackup = true
                        } label: {
                            Label("Restore Backup", systemImage: "externaldrive.badge.checkmark")
                        }

                        Button {
                            prepareLatestAutomaticBackupRestore()
                        } label: {
                            Label("Restore Latest Automatic Backup", systemImage: "clock.arrow.circlepath")
                        }
                        .disabled(!hasAutomaticBackup)
                    } label: {
                        Label("Data", systemImage: "externaldrive")
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        prefersDarkMode.toggle()
                    } label: {
                        Label(
                            prefersDarkMode ? "Light Mode" : "Dark Mode",
                            systemImage: prefersDarkMode ? "sun.max.fill" : "moon.fill"
                        )
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isComposingMarketingEmail = true
                    } label: {
                        Label("Marketing Email", systemImage: "megaphone")
                    }
                    .disabled(marketingEmailRecipients.isEmpty)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: addStudent) {
                        Label("Add Student", systemImage: "plus")
                    }
                }
            }
            .toolbarBackground(Color(uiColor: .systemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $isExportingStudents) {
                StudentExportView(students: students)
            }
            .sheet(isPresented: $isComposingMarketingEmail) {
                MarketingEmailView(recipients: marketingEmailRecipients)
            }
            .fileExporter(
                isPresented: $isExportingBackup,
                document: backupDocument,
                contentType: .json,
                defaultFilename: GolfCoachBackupSnapshot.fileName
            ) { result in
                switch result {
                case .success:
                    showBackupStatus(
                        title: "Backup Saved",
                        message: "Student profiles, packages, appointments, notes, and video metadata were saved. Videos are stored locally on this device and are not included in automatic backups."
                    )
                case .failure(let error):
                    showBackupStatus(title: "Backup Failed", message: error.localizedDescription)
                }
            }
            .fileImporter(isPresented: $isImportingBackup, allowedContentTypes: [.json]) { result in
                prepareRestore(from: result)
            }
            .alert("Restore Backup", isPresented: $isConfirmingBackupRestore) {
                Button("Replace Current Student Data", role: .destructive) {
                    restorePendingBackup()
                }
                Button("Cancel", role: .cancel) {
                    backupPendingRestore = nil
                }
            } message: {
                Text(backupRestoreConfirmationMessage)
            }
            .alert("Delete Student", isPresented: $isConfirmingStudentDeletion) {
                Button("Delete Student", role: .destructive) {
                    deletePendingStudents()
                }
                Button("Cancel", role: .cancel) {
                    studentsPendingDeletion = []
                }
            } message: {
                Text(studentDeletionConfirmationMessage)
            }
            .alert(backupStatusTitle, isPresented: $isShowingBackupStatus) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(backupStatusMessage)
            }
            .task {
                updateAutomaticBackupAvailability()
                createAutomaticBackupIfNeeded()
                restoreRequestedStudent()

                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(15 * 60))
                    guard !Task.isCancelled else { return }
                    createAutomaticBackupIfNeeded()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    createAutomaticBackupIfNeeded()
                }
            }
            .onChange(of: restorationRequest) { _, _ in
                restoreRequestedStudent()
            }
        }
    }

    private func addStudent() {
        let student = Student()
        modelContext.insert(student)
    }

    private func openStudent(_ student: Student) {
        guard !navigationPath.contains(where: { $0.persistentModelID == student.persistentModelID }) else {
            return
        }

        sessionStateManager.selectStudent(student)
        highlightedStudentID = student.persistentModelID
        withAnimation(.easeOut(duration: 0.18)) {
            selectedStudentPrompt = student.name
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            navigationPath.append(student)

            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.easeIn(duration: 0.12)) {
                selectedStudentPrompt = nil
            }
            highlightedStudentID = nil
        }
    }

    private func restoreRequestedStudent() {
        guard let request = restorationRequest,
              let student = students.first(where: {
                  sessionStateManager.matches($0, storedIdentifier: request.selectedStudentID)
              }) else {
            return
        }

        if navigationPath.last?.persistentModelID != student.persistentModelID {
            navigationPath = [student]
        }
    }

    private func restoredSession(for student: Student) -> LastSessionState? {
        guard let request = restorationRequest,
              sessionStateManager.matches(student, storedIdentifier: request.selectedStudentID) else {
            return nil
        }
        return request
    }

    private var studentDeletionConfirmationMessage: String {
        if studentsPendingDeletion.count == 1, let student = studentsPendingDeletion.first {
            return "Delete \(student.name)? This removes their packages, lessons, notes, and videos from the app."
        }

        return "Delete \(studentsPendingDeletion.count) students? This removes their packages, lessons, notes, and videos from the app."
    }

    private func stageStudentsForDeletion(offsets: IndexSet) {
        studentsPendingDeletion = offsets.map { filteredStudents[$0] }
        isConfirmingStudentDeletion = !studentsPendingDeletion.isEmpty
    }

    private func deletePendingStudents() {
        for student in studentsPendingDeletion {
            modelContext.delete(student)
        }
        studentsPendingDeletion = []
    }

    private var backupRestoreConfirmationMessage: String {
        guard let backupPendingRestore else { return "" }
        return "Replace current student data with \(backupPendingRestore.students.count) student record(s) from this backup? Existing student records will be deleted. Video files are not restored."
    }

    private func createBackup() {
        let snapshot = GolfCoachBackupSnapshot(students: students)
        backupDocument = GolfCoachBackupDocument(snapshot: snapshot)
        isExportingBackup = true
    }

    private func prepareRestore(from result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessedResource = url.startAccessingSecurityScopedResource()
            defer {
                if accessedResource {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            let snapshot = try GolfCoachBackupSnapshot.decode(from: data)
            backupPendingRestore = snapshot
            isConfirmingBackupRestore = true
        } catch {
            showBackupStatus(title: "Restore Failed", message: error.localizedDescription)
        }
    }

    private func prepareLatestAutomaticBackupRestore() {
        do {
            guard let snapshot = try AutomaticBackupStore.latestSnapshot() else {
                showBackupStatus(title: "No Automatic Backup", message: "There is no automatic backup available to restore.")
                updateAutomaticBackupAvailability()
                return
            }
            backupPendingRestore = snapshot
            isConfirmingBackupRestore = true
        } catch {
            showBackupStatus(title: "Restore Failed", message: error.localizedDescription)
        }
    }

    private func restorePendingBackup() {
        guard let backupPendingRestore else { return }

        navigationPath.removeAll()
        for student in students {
            modelContext.delete(student)
        }
        for backupStudent in backupPendingRestore.students {
            modelContext.insert(backupStudent.makeStudent())
        }

        do {
            try modelContext.save()
            self.backupPendingRestore = nil
            showBackupStatus(
                title: "Backup Restored",
                message: "\(backupPendingRestore.students.count) student record(s) restored. Videos are stored locally on this device and are not included in automatic backups."
            )
        } catch {
            showBackupStatus(title: "Restore Failed", message: error.localizedDescription)
        }
    }

    private func showBackupStatus(title: String, message: String) {
        backupStatusTitle = title
        backupStatusMessage = message
        isShowingBackupStatus = true
    }

    private func createAutomaticBackupIfNeeded() {
        guard AutomaticBackupStore.isBackupDue() else {
            updateAutomaticBackupAvailability()
            return
        }

        do {
            try AutomaticBackupStore.save(snapshot: GolfCoachBackupSnapshot(students: students))
            updateAutomaticBackupAvailability()
        } catch {
            showBackupStatus(title: "Automatic Backup Failed", message: error.localizedDescription)
        }
    }

    private func updateAutomaticBackupAvailability() {
        hasAutomaticBackup = AutomaticBackupStore.hasBackup
    }
}

private enum StudentDirectoryPalette {
    private static func adaptiveColor(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    static let pageBackground = LinearGradient(
        colors: [
            adaptiveColor(
                light: UIColor(red: 0.94, green: 0.97, blue: 0.96, alpha: 1),
                dark: UIColor(red: 0.07, green: 0.10, blue: 0.10, alpha: 1)
            ),
            adaptiveColor(
                light: UIColor(red: 0.91, green: 0.94, blue: 0.98, alpha: 1),
                dark: UIColor(red: 0.07, green: 0.09, blue: 0.14, alpha: 1)
            )
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let primary = adaptiveColor(
        light: UIColor(red: 0.08, green: 0.16, blue: 0.23, alpha: 1),
        dark: UIColor(red: 0.90, green: 0.94, blue: 0.97, alpha: 1)
    )
    static let secondary = adaptiveColor(
        light: UIColor(red: 0.34, green: 0.43, blue: 0.50, alpha: 1),
        dark: UIColor(red: 0.67, green: 0.74, blue: 0.80, alpha: 1)
    )
    static let fairway = adaptiveColor(
        light: UIColor(red: 0.10, green: 0.42, blue: 0.30, alpha: 1),
        dark: UIColor(red: 0.34, green: 0.79, blue: 0.58, alpha: 1)
    )
    static let gold = adaptiveColor(
        light: UIColor(red: 0.72, green: 0.52, blue: 0.18, alpha: 1),
        dark: UIColor(red: 0.93, green: 0.72, blue: 0.34, alpha: 1)
    )
    static let brandGreen = adaptiveColor(
        light: UIColor(red: 0.03, green: 0.29, blue: 0.20, alpha: 1),
        dark: UIColor(red: 0.38, green: 0.84, blue: 0.65, alpha: 1)
    )
    static let brandGold = Color(red: 0.72, green: 0.57, blue: 0.26)
    static let sky = adaptiveColor(
        light: UIColor(red: 0.15, green: 0.38, blue: 0.58, alpha: 1),
        dark: UIColor(red: 0.35, green: 0.68, blue: 0.93, alpha: 1)
    )
    static let rowBackground = Color(uiColor: .secondarySystemBackground).opacity(0.86)
    static let cardStroke = Color(uiColor: .separator).opacity(0.25)
    static let iconBackground = Color(uiColor: .secondarySystemBackground)
}

struct StudentDirectoryEmptyState: View {
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(StudentDirectoryPalette.fairway.opacity(0.12))
                    .frame(width: 92, height: 92)

                Image(systemName: "figure.golf")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(StudentDirectoryPalette.fairway)
            }

            VStack(spacing: 6) {
                Text("No Students Yet")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(StudentDirectoryPalette.primary)

                Text("Add a student to start tracking packages, lesson progress, payments, and swing videos.")
                    .font(.subheadline)
                    .foregroundStyle(StudentDirectoryPalette.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 56)
    }
}

struct StudentDirectoryOverview: View {
    let students: [Student]
    let totalStudentCount: Int

    private var activeStudents: Int {
        students.filter { $0.remainingValue > 0 }.count
    }

    private var totalRemainingCredit: Decimal {
        students.reduce(Decimal.zero) { $0 + $1.remainingValue }
    }

    private var totalVideos: Int {
        students.reduce(0) { $0 + $1.videos.count + $1.coachAnalysisVideos.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(StudentDirectoryPalette.fairway.opacity(0.14))
                    Image(systemName: "flag.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(StudentDirectoryPalette.fairway)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Student Roster")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(StudentDirectoryPalette.primary)
                    if totalStudentCount == students.count {
                        Text("Manage lesson balances, payments, notes, and swing analysis from one place.")
                            .font(.caption)
                            .foregroundStyle(StudentDirectoryPalette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Showing \(students.count) of \(totalStudentCount) students.")
                            .font(.caption)
                            .foregroundStyle(StudentDirectoryPalette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()
            }

            HStack(spacing: 8) {
                StudentDirectoryMetric(title: "Students", value: "\(students.count)", tint: StudentDirectoryPalette.sky)
                StudentDirectoryMetric(title: "Active", value: "\(activeStudents)", tint: StudentDirectoryPalette.fairway)
                StudentDirectoryMetric(title: "Credit", value: CurrencyFormatter.string(from: totalRemainingCredit), tint: StudentDirectoryPalette.gold)
                StudentDirectoryMetric(title: "Videos", value: "\(totalVideos)", tint: StudentDirectoryPalette.primary)
            }
        }
        .padding(16)
        .background(StudentDirectoryPalette.rowBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(StudentDirectoryPalette.cardStroke, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 5)
    }
}

struct StudentDirectoryMetric: View {
    let title: LocalizedStringKey
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(StudentDirectoryPalette.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct StudentSelectionPrompt: View {
    let studentName: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("Opening Student")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(studentName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.green.opacity(0.45), lineWidth: 1)
        }
        .shadow(radius: 8)
        .allowsHitTesting(false)
    }
}

struct StudentRow: View {
    let student: Student
    var isHighlighted = false

    private var initials: String {
        let parts = student.name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let value = String(parts).uppercased()
        return value.isEmpty ? "S" : value
    }

    private var lastLessonText: String {
        guard let lastLesson = student.lessons.sorted(by: { $0.scheduledAt > $1.scheduledAt }).first else {
            return "No lessons scheduled"
        }

        return lastLesson.scheduledAt.formatted(.dateTime.month(.abbreviated).day())
    }

    private var remainingTint: Color {
        student.remainingValue > 0 ? StudentDirectoryPalette.fairway : StudentDirectoryPalette.secondary
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(StudentDirectoryPalette.sky.opacity(0.14))
                Text(initials)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(StudentDirectoryPalette.sky)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(student.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(StudentDirectoryPalette.primary)
                        .lineLimit(1)

                    Spacer()

                    HStack(spacing: 5) {
                        Image(systemName: student.remainingValue > 0 ? "checkmark.seal.fill" : "exclamationmark.circle")
                            .font(.caption2.weight(.semibold))
                        Text("\(CurrencyFormatter.string(from: student.remainingValue)) balance")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(remainingTint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(remainingTint.opacity(0.10), in: Capsule())
                }

                HStack(spacing: 14) {
                    StudentRowInfo(systemImage: "creditcard", text: CurrencyFormatter.string(from: student.totalPaid))
                    StudentRowInfo(systemImage: "calendar", text: lastLessonText)
                    StudentRowInfo(systemImage: "video", text: "\(student.videos.count + student.coachAnalysisVideos.count)")
                }

                HStack(spacing: 12) {
                    if !student.phoneNumber.isEmpty {
                        StudentRowInfo(systemImage: "phone", text: student.phoneNumber)
                    }
                    if !student.email.isEmpty {
                        StudentRowInfo(systemImage: "envelope", text: student.email)
                    }
                }
                .lineLimit(1)
            }
        }
        .padding(14)
        .background(isHighlighted ? StudentDirectoryPalette.sky.opacity(0.16) : StudentDirectoryPalette.rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHighlighted ? StudentDirectoryPalette.sky.opacity(0.35) : StudentDirectoryPalette.cardStroke, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        .animation(.easeInOut(duration: 0.12), value: isHighlighted)
    }
}

struct StudentRowInfo: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label {
            Text(text)
                .lineLimit(1)
        } icon: {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
        }
        .font(.caption)
        .foregroundStyle(StudentDirectoryPalette.secondary)
    }
}


struct MarketingEmailView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("marketingSenderEmail") private var senderEmail = ""
    let recipients: [String]
    @State private var subject = ""
    @State private var messageBody = ""
    @State private var confirmsPermission = false
    @State private var isShowingMailComposer = false
    @State private var statusTitle = ""
    @State private var statusMessage = ""
    @State private var isShowingStatus = false

    private var canComposeEmail: Bool {
        !recipients.isEmpty &&
        isValidSenderEmail &&
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        confirmsPermission
    }

    private var isValidSenderEmail: Bool {
        let email = senderEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.contains("@") && email.contains(".")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Audience") {
                    LabeledContent("Students with Email", value: "\(recipients.count)")
                    Label("Recipients are hidden from each other using Bcc.", systemImage: "lock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Sender") {
                    TextField("Your business email address", text: $senderEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("This address appears in To. Students remain in Bcc.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Promotion") {
                    TextField("Subject", text: $subject)
                    TextField("Event or promotion message", text: $messageBody, axis: .vertical)
                        .lineLimit(8...14)
                }

                Section {
                    Toggle("I have permission to send this promotion", isOn: $confirmsPermission)
                } footer: {
                    Text("Include your business identity and an unsubscribe instruction in promotional email.")
                }
            }
            .navigationTitle("Marketing Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Compose") {
                        if MFMailComposeViewController.canSendMail() {
                            isShowingMailComposer = true
                        } else {
                            statusTitle = "Mail Unavailable"
                            statusMessage = "Set up Mail on this iPhone before composing a marketing email."
                            isShowingStatus = true
                        }
                    }
                    .disabled(!canComposeEmail)
                }
            }
            .sheet(isPresented: $isShowingMailComposer) {
                MarketingMailComposerView(
                    toRecipient: senderEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                    blindCopyRecipients: recipients,
                    subject: subject,
                    body: messageBody,
                    onFinish: handleEmailResult
                )
            }
            .alert(statusTitle, isPresented: $isShowingStatus) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(statusMessage)
            }
        }
    }

    private func handleEmailResult(_ result: MFMailComposeResult, error: Error?) {
        if let error {
            statusTitle = "Email Failed"
            statusMessage = error.localizedDescription
        } else {
            switch result {
            case .sent:
                statusTitle = "Email Queued"
                statusMessage = "Mail accepted the promotional email for sending."
            case .saved:
                statusTitle = "Draft Saved"
                statusMessage = "The promotional email was saved as a draft."
            case .cancelled:
                statusTitle = "Email Cancelled"
                statusMessage = "The promotional email was not sent."
            case .failed:
                statusTitle = "Email Failed"
                statusMessage = "Mail could not queue the promotional email."
            @unknown default:
                statusTitle = "Email Status Unknown"
                statusMessage = "Check Mail for the status of this message."
            }
        }

        isShowingStatus = true
    }
}

struct StudentExportView: View {
    @Environment(\.dismiss) private var dismiss
    let students: [Student]
    @State private var recipients = ""
    @State private var exportURL: URL?
    @State private var exportData: Data?
    @State private var exportError: String?
    @State private var isShowingMailComposer = false
    @State private var emailStatus: EmailStatus?
    @State private var isShowingEmailStatus = false

    var recipientList: [String] {
        recipients
            .split { $0 == "," || $0 == ";" || $0.isWhitespace || $0.isNewline }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    var canEmailExport: Bool {
        exportData != nil && !recipientList.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Excel Export") {
                    LabeledContent("Students", value: "\(students.count)")

                    if let exportURL {
                        Label(exportURL.lastPathComponent, systemImage: "tablecells")
                            .foregroundStyle(.green)
                    }

                    if let exportError {
                        Text(exportError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Email") {
                    TextField("recipient@example.com, second@example.com", text: $recipients, axis: .vertical)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(2...4)

                    Button {
                        emailStatus = nil
                        if MFMailComposeViewController.canSendMail() {
                            isShowingMailComposer = true
                        } else {
                            emailStatus = EmailStatus.mailUnavailable
                            isShowingEmailStatus = true
                        }
                    } label: {
                        Label("Email Excel File", systemImage: "envelope")
                    }
                    .disabled(!canEmailExport)

                    if let emailStatus {
                        Label(emailStatus.title, systemImage: emailStatus.systemImage)
                            .foregroundStyle(emailStatus.tint)

                        Text(emailStatus.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !MFMailComposeViewController.canSendMail() {
                        Text("Mail is not configured on this device. Use Share Excel File, or test email on an iPhone with a Mail account.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let exportURL {
                    Section("Share") {
                        ShareLink(item: exportURL) {
                            Label("Share Excel File", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .navigationTitle("Export Students")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                createExportFile()
            }
            .sheet(isPresented: $isShowingMailComposer) {
                if let exportData {
                    MailComposerView(
                        recipients: recipientList,
                        subject: "Golf Coach Student Export",
                        body: "Attached is the current student export from Golf Coach.",
                        attachmentData: exportData,
                        attachmentMimeType: "text/csv",
                        attachmentFileName: StudentExporter.fileName
                    ) { status in
                        emailStatus = status
                        isShowingEmailStatus = true
                    }
                }
            }
            .alert(emailStatus?.title ?? "Email Status", isPresented: $isShowingEmailStatus) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(emailStatus?.message ?? "")
            }
        }
    }

    private func createExportFile() {
        do {
            let result = try StudentExporter.makeExportFile(students: students)
            exportURL = result.url
            exportData = result.data
            exportError = nil
        } catch {
            exportError = error.localizedDescription
        }
    }
}

private enum StudentUndoAction {
    case lessonCharge(LessonPackage, LessonCharge)
    case packageDeletion([LessonPackage])

    var buttonTitle: String {
        switch self {
        case .lessonCharge:
            return "Restore Last Deducted Fee"
        case .packageDeletion:
            return "Restore Deleted Package"
        }
    }
}

private enum StudentDetailSectionTint {
    static let studentInfo = Color.blue.opacity(0.10)
    static let notes = Color.mint.opacity(0.10)
    static let account = Color.green.opacity(0.10)
    static let packages = Color.orange.opacity(0.12)
    static let lessons = Color.purple.opacity(0.10)
    static let videos = Color.indigo.opacity(0.10)
    static let coachAnalysis = Color.cyan.opacity(0.10)
}

struct StudentDetailView: View {
    @Environment(\.openURL) private var openURL
    @Bindable var student: Student
    let onPlayVideo: (LessonVideo, Student) -> Void
    let onPlayCoachAnalysis: (CoachAnalysisVideo) -> Void
    let sessionStateManager: SessionStateManager
    let onRestorationHandled: () -> Void
    @State private var name: String
    @State private var phoneNumber: String
    @State private var email: String
    @State private var birthday: Date?
    @State private var referralPersonName: String
    @State private var yearsOfExperience: String
    @State private var handicap: String
    @State private var golfGoal: String
    @State private var jobInfo: String
    @State private var isCapturingPhoto = false
    @State private var isShowingPhotoOptions = false
    @State private var isShowingPhotoLibrary = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isAddingPackage = false
    @State private var isAddingLesson = false
    @State private var isAddingVideo = false
    @State private var newVideoDefaultDate: Date = .now
    @State private var isCapturingSwingVideo = false
    @State private var captureVideoLessonDate: Date = .now
    @State private var videoCaptureError: String?
    @State private var isShowingVideoCaptureError = false
    @State private var processedCaptureURLs: Set<URL> = []
    @State private var sessionNoteToShare: LessonSessionNote?
    @State private var isAddingSessionNote = false
    @State private var sessionNoteDefaultDate: Date = .now
    @State private var sessionNoteForEditing: LessonSessionNote?
    @State private var sessionVideoForEditing: LessonVideo?
    @State private var sessionAnalysisForEditing: CoachAnalysisVideo?
    @State private var packageToDeduct: LessonPackage?
    @State private var lessonEmailBody = ""
    @State private var isShowingLessonEmailComposer = false
    @State private var pendingLessonConfirmationCharge: LessonCharge?
    @State private var isConfirmingLessonEmail = false
    @State private var accountUpdateEmailPromptMessage: String?
    @State private var isConfirmingAccountUpdateEmail = false
    @State private var lessonStatusMessage: String?
    @State private var isShowingLessonStatus = false
    @State private var packagesPendingDeletion: [LessonPackage] = []
    @State private var isConfirmingPackageDeletion = false
    @State private var packageDeletionMessageRecipients: [String] = []
    @State private var packageDeletionMessageBody = ""
    @State private var isShowingPackageDeletionMessageComposer = false
    @State private var packageDeletionStatusMessage: String?
    @State private var isShowingPackageDeletionStatus = false
    @State private var lastUndoAction: StudentUndoAction?
    @State private var isConfirmingUndoAction = false
    @State private var packagePendingReversal: LessonPackage?
    @State private var isConfirmingPackageReversal = false
    @State private var isConfirmingFinalPackageReversal = false
    @State private var chargePackagePendingReversal: LessonPackage?
    @State private var chargePendingReversal: LessonCharge?
    @State private var isConfirmingChargeReversal = false
    @State private var isConfirmingFinalChargeReversal = false
    @State private var undoStatusMessage: String?
    @State private var isShowingUndoStatus = false
    @State private var restoredLessonDate: Date?
    @State private var shouldRestoreComparison: Bool

    init(
        student: Student,
        onPlayVideo: @escaping (LessonVideo, Student) -> Void,
        onPlayCoachAnalysis: @escaping (CoachAnalysisVideo) -> Void,
        sessionStateManager: SessionStateManager,
        restoredSession: LastSessionState? = nil,
        onRestorationHandled: @escaping () -> Void = {}
    ) {
        self.student = student
        self.onPlayVideo = onPlayVideo
        self.onPlayCoachAnalysis = onPlayCoachAnalysis
        self.sessionStateManager = sessionStateManager
        self.onRestorationHandled = onRestorationHandled
        _name = State(initialValue: student.name)
        _phoneNumber = State(initialValue: student.phoneNumber)
        _email = State(initialValue: student.email)
        _birthday = State(initialValue: student.birthday)
        _referralPersonName = State(initialValue: student.referralPersonName ?? "")
        _yearsOfExperience = State(initialValue: student.yearsOfExperience ?? "")
        _handicap = State(initialValue: student.handicap ?? "")
        _golfGoal = State(initialValue: student.golfGoal ?? "")
        _jobInfo = State(initialValue: student.jobInfo ?? "")
        let availableDates = LessonTimelineBuilder.days(for: student).map(\.date)
        let validRestoredDate = restoredSession?.selectedLessonDate.flatMap { savedDate in
            availableDates.first { Calendar.current.isDate($0, inSameDayAs: savedDate) }
        }
        _restoredLessonDate = State(initialValue: validRestoredDate)
        _shouldRestoreComparison = State(initialValue: validRestoredDate != nil && restoredSession?.hasComparison == true)
    }

    var body: some View {
        undoAlertDetailView
    }

    private var navigationDetailView: some View {
        detailForm
        .navigationTitle(student.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            captureVideoToolbarItem
        }
        .navigationDestination(isPresented: restoringLessonDayBinding) {
            if let restoredLessonDate {
                lessonDayDetailView(for: restoredLessonDate, restoringComparison: shouldRestoreComparison)
            }
        }
        .task {
            if restoredLessonDate != nil {
                onRestorationHandled()
            }
        }
    }

    private var editorSheetsDetailView: some View {
        navigationDetailView
        .sheet(isPresented: $isCapturingPhoto) {
            CameraImagePicker { image in
                savePhoto(image)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isAddingPackage) {
            AddPackageView(student: student)
        }
        .sheet(isPresented: $isAddingLesson) {
            AddLessonView(student: student)
        }
        .sheet(isPresented: $isAddingVideo) {
            AddVideoView(student: student, defaultDate: newVideoDefaultDate)
        }
        .fullScreenCover(isPresented: $isCapturingSwingVideo) {
            VideoCaptureView { url in
                saveCapturedSwingVideo(from: url)
            }
            .ignoresSafeArea()
        }
        .sheet(item: $sessionNoteToShare) { note in
            SessionNoteShareView(note: note, studentName: student.name, studentEmail: student.email)
        }
        .sheet(isPresented: $isAddingSessionNote) {
            EditSessionNoteView(student: student, defaultDate: sessionNoteDefaultDate)
        }
        .sheet(item: $sessionNoteForEditing) { note in
            EditSessionNoteView(existingNote: note)
        }
        .sheet(item: $sessionVideoForEditing) { video in
            EditVideoView(video: video)
        }
        .sheet(item: $sessionAnalysisForEditing) { analysis in
            EditCoachAnalysisView(analysis: analysis)
        }
        .alert("Video Capture Failed", isPresented: $isShowingVideoCaptureError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(videoCaptureError ?? "The video could not be saved.")
        }
    }

    private var lessonMessagingDetailView: some View {
        editorSheetsDetailView
        .sheet(item: $packageToDeduct) { package in
            LogSessionChargeView(package: package) { charge in
                recordSessionCharge(charge, from: package)
            }
        }
        .sheet(isPresented: $isShowingLessonEmailComposer) {
            LessonEmailComposerView(
                recipients: [student.email.trimmingCharacters(in: .whitespacesAndNewlines)],
                subject: "Golf Lesson Account Statement",
                body: lessonEmailBody,
                onFinish: { resultMessage in
                    if let resultMessage {
                        lessonStatusMessage = resultMessage
                        isShowingLessonStatus = true
                    }
                }
            )
        }
        .alert(
            "Send Confirmation Email?",
            isPresented: $isConfirmingLessonEmail,
            presenting: pendingLessonConfirmationCharge
        ) { charge in
            Button("Send Email") {
                prepareAccountStatementEmail(latestCharge: charge)
                pendingLessonConfirmationCharge = nil
            }
            Button("Not Now", role: .cancel) {
                pendingLessonConfirmationCharge = nil
            }
        } message: { _ in
            Text("The lesson fee has been recorded. Would you like to email the updated account statement to \(student.name)?")
        }
        .alert("Lesson Update", isPresented: $isShowingLessonStatus, presenting: lessonStatusMessage) { _ in
            Button("OK", role: .cancel) { }
        } message: { msg in
            Text(msg)
        }
    }

    private var packageDeletionDetailView: some View {
        lessonMessagingDetailView
        .alert("Delete Package", isPresented: $isConfirmingPackageDeletion) {
            Button("Text Student & Delete", role: .destructive) {
                preparePackageDeletionMessage()
            }
            Button("Cancel", role: .cancel) {
                packagesPendingDeletion = []
            }
        } message: {
            Text(packageDeletionConfirmationMessage)
        }
        .sheet(isPresented: $isShowingPackageDeletionMessageComposer) {
            MessageComposerView(
                recipients: packageDeletionMessageRecipients,
                body: packageDeletionMessageBody,
                onFinish: { resultMessage in
                    handlePackageDeletionMessageResult(resultMessage)
                }
            )
        }
        .alert("Package Update", isPresented: $isShowingPackageDeletionStatus, presenting: packageDeletionStatusMessage) { _ in
            Button("OK", role: .cancel) { }
        } message: { message in
            Text(message)
        }
    }

    private var undoAlertDetailView: some View {
        packageDeletionDetailView
        .alert("Confirm Reversal", isPresented: $isConfirmingUndoAction, presenting: lastUndoAction) { _ in
            Button("Reverse Transaction", role: .destructive) {
                undoLastAction()
            }
            Button("Cancel", role: .cancel) { }
        } message: { action in
            Text(undoConfirmationMessage(for: action))
        }
        .alert(
            "Remove Added Payment",
            isPresented: $isConfirmingPackageReversal,
            presenting: packagePendingReversal
        ) { package in
            Button("Continue", role: .destructive) {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    guard packagePendingReversal != nil else { return }
                    isConfirmingFinalPackageReversal = true
                }
            }
            Button("Cancel", role: .cancel) {
                packagePendingReversal = nil
            }
        } message: { package in
            Text("Remove the \(package.packageType.localizedName) payment of \(CurrencyFormatter.string(from: package.totalPaid))? Any lesson charges recorded against this payment will also be removed.")
        }
        .alert(
            "Final Confirmation",
            isPresented: $isConfirmingFinalPackageReversal,
            presenting: packagePendingReversal
        ) { package in
            Button("Delete Whole Package", role: .destructive) {
                reversePayment(package)
            }
            Button("Cancel", role: .cancel) {
                packagePendingReversal = nil
            }
        } message: { package in
            Text("Are you sure? This permanently removes the \(package.packageType.localizedName) payment and all of its recorded lesson fees.")
        }
        .alert(
            "Reverse Deducted Lesson Fee",
            isPresented: $isConfirmingChargeReversal,
            presenting: chargePendingReversal
        ) { charge in
            Button("Continue", role: .destructive) {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    guard chargePendingReversal != nil else { return }
                    isConfirmingFinalChargeReversal = true
                }
            }
            Button("Cancel", role: .cancel) {
                chargePendingReversal = nil
                chargePackagePendingReversal = nil
            }
        } message: { charge in
            Text("Remove the lesson charge of \(CurrencyFormatter.string(from: charge.amount)) from \(charge.chargedAt.formatted(date: .abbreviated, time: .omitted))? The credit will be restored.")
        }
        .alert(
            "Final Confirmation",
            isPresented: $isConfirmingFinalChargeReversal,
            presenting: chargePendingReversal
        ) { charge in
            Button("Restore Deducted Fee", role: .destructive) {
                reverseLessonCharge(charge)
            }
            Button("Cancel", role: .cancel) {
                chargePendingReversal = nil
                chargePackagePendingReversal = nil
            }
        } message: { charge in
            Text("Are you sure? This removes the recorded lesson fee of \(CurrencyFormatter.string(from: charge.amount)) and returns that amount to the student's balance.")
        }
        .alert(
            "Send Confirmation Email?",
            isPresented: $isConfirmingAccountUpdateEmail,
            presenting: accountUpdateEmailPromptMessage
        ) { _ in
            Button("Send Email") {
                prepareAccountStatementEmail()
                accountUpdateEmailPromptMessage = nil
            }
            Button("Not Now", role: .cancel) {
                accountUpdateEmailPromptMessage = nil
            }
        } message: { message in
            Text(message)
        }
        .alert("Undo Complete", isPresented: $isShowingUndoStatus, presenting: undoStatusMessage) { _ in
            Button("OK", role: .cancel) { }
        } message: { message in
            Text(message)
        }
    }

    private var detailForm: some View {
        Form {
            studentInformationSection
            bioSection
            accountSection
            packageSection
            LessonTimelineSection(
                student: student,
                sessionStateManager: sessionStateManager,
                onCaptureVideo: { date in
                    startVideoCapture(for: date)
                },
                onAddVideo: { date in
                    newVideoDefaultDate = date
                    isAddingVideo = true
                },
                onPlayVideo: onPlayVideo,
                onPlayCoachAnalysis: onPlayCoachAnalysis,
                onShareNote: { sessionNoteToShare = $0 },
                onAddSessionNote: { date in
                    sessionNoteDefaultDate = date
                    isAddingSessionNote = true
                },
                onEditNote: { sessionNoteForEditing = $0 },
                onEditVideo: { sessionVideoForEditing = $0 },
                onEditAnalysis: { sessionAnalysisForEditing = $0 }
            )
        }
        .onChange(of: name) { saveStudentDetails() }
        .onChange(of: phoneNumber) { saveStudentDetails() }
        .onChange(of: email) { saveStudentDetails() }
        .onChange(of: birthday) { saveStudentDetails() }
        .onChange(of: referralPersonName) { saveStudentDetails() }
        .onChange(of: yearsOfExperience) { saveStudentDetails() }
        .onChange(of: handicap) { saveStudentDetails() }
        .onChange(of: golfGoal) { saveStudentDetails() }
        .onChange(of: jobInfo) { saveStudentDetails() }
        .photosPicker(isPresented: $isShowingPhotoLibrary, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) {
            guard let item = selectedPhotoItem else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    if let image = UIImage(data: data) {
                        savePhoto(image)
                    }
                }
                selectedPhotoItem = nil
            }
        }
    }

    private var restoringLessonDayBinding: Binding<Bool> {
        Binding(
            get: { restoredLessonDate != nil },
            set: { isPresented in
                if !isPresented {
                    restoredLessonDate = nil
                    shouldRestoreComparison = false
                }
            }
        )
    }

    private func lessonDayDetailView(for date: Date, restoringComparison: Bool) -> some View {
        LessonDayDetailView(
            student: student,
            date: date,
            sessionStateManager: sessionStateManager,
            restoreComparisonOnAppear: restoringComparison,
            onCaptureVideo: { startVideoCapture(for: $0) },
            onAddVideo: {
                newVideoDefaultDate = $0
                isAddingVideo = true
            },
            onPlayVideo: onPlayVideo,
            onPlayCoachAnalysis: onPlayCoachAnalysis,
            onShareNote: { sessionNoteToShare = $0 },
            onAddSessionNote: {
                sessionNoteDefaultDate = $0
                isAddingSessionNote = true
            },
            onEditNote: { sessionNoteForEditing = $0 },
            onEditVideo: { sessionVideoForEditing = $0 },
            onEditAnalysis: { sessionAnalysisForEditing = $0 }
        )
    }

    @ToolbarContentBuilder
    private var captureVideoToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                startVideoCapture()
            } label: {
                Label("Capture Video", systemImage: "camera.fill")
            }
        }
    }

    private var studentInformationSection: some View {
        Section("Student Information") {
            HStack {
                Spacer()
                Button {
                    isShowingPhotoOptions = true
                } label: {
                    if let data = student.photoData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 90, height: 90)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.secondary)
                            .frame(width: 90, height: 90)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.vertical, 8)
            .confirmationDialog("Student Photo", isPresented: $isShowingPhotoOptions) {
                Button("Take Photo") { isCapturingPhoto = true }
                Button("Choose from Library") { isShowingPhotoLibrary = true }
                if student.photoData != nil {
                    Button("Remove Photo", role: .destructive) { student.photoData = nil }
                }
                Button("Cancel", role: .cancel) { }
            }
            TextField("Name", text: $name)
            HStack {
                TextField("Phone", text: $phoneNumber)
                    .keyboardType(.phonePad)
                if let phoneURL {
                    Button {
                        openURL(phoneURL)
                    } label: {
                        Image(systemName: "phone.fill")
                            .foregroundStyle(StudentDirectoryPalette.fairway)
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                if let emailURL {
                    Button {
                        openURL(emailURL)
                    } label: {
                        Image(systemName: "envelope.fill")
                            .foregroundStyle(StudentDirectoryPalette.sky)
                    }
                    .buttonStyle(.borderless)
                }
            }
            Toggle("Birthday on File", isOn: hasBirthday)
            if birthday != nil {
                DatePicker(
                    "Birthday",
                    selection: birthdaySelection,
                    in: ...Date.now,
                    displayedComponents: .date
                )
            }
            TextField("Referral Person Name", text: $referralPersonName)
        }
        .listRowBackground(StudentDetailSectionTint.studentInfo)
    }

    private var phoneURL: URL? {
        let allowedCharacters = CharacterSet(charactersIn: "+0123456789")
        let phoneNumber = phoneNumber.unicodeScalars
            .filter { allowedCharacters.contains($0) }
            .map(String.init)
            .joined()
        guard !phoneNumber.isEmpty else { return nil }
        return URL(string: "tel:\(phoneNumber)")
    }

    private var emailURL: URL? {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else { return nil }
        return URL(string: "mailto:\(email)")
    }

    private var hasBirthday: Binding<Bool> {
        Binding(
            get: { birthday != nil },
            set: { includesBirthday in
                birthday = includesBirthday ? (birthday ?? .now) : nil
            }
        )
    }

    private var birthdaySelection: Binding<Date> {
        Binding(
            get: { birthday ?? .now },
            set: { birthday = $0 }
        )
    }

    private var bioSection: some View {
        Section("Student Bio") {
            LabeledContent("Experience") {
                TextField("e.g. 3 years", text: $yearsOfExperience)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Handicap") {
                TextField("e.g. 14.2", text: $handicap)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Occupation") {
                TextField("e.g. Engineer", text: $jobInfo)
                    .multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Golf Goal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("What does the student want to achieve?", text: $golfGoal, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .listRowBackground(StudentDetailSectionTint.notes)
    }

    private var accountSection: some View {
        Section("Account") {
            LabeledContent("Remaining Credit", value: CurrencyFormatter.string(from: student.remainingValue))
            LabeledContent("Total Paid", value: CurrencyFormatter.string(from: student.totalPaid))
            if let activePackage = student.activePackage {
                LabeledContent("Active Package", value: activePackage.packageType.localizedName)
            }

            Button {
                isAddingPackage = true
            } label: {
                Label("Add Payment / Package", systemImage: "creditcard")
            }

            Button {
                isAddingLesson = true
            } label: {
                Label("Schedule Lesson", systemImage: "calendar.badge.plus")
            }

            Button {
                prepareAccountStatementEmail()
            } label: {
                Label("Email Account Statement", systemImage: "envelope")
            }

            if let lastUndoAction {
                Button {
                    isConfirmingUndoAction = true
                } label: {
                    Label(lastUndoAction.buttonTitle, systemImage: "arrow.uturn.backward")
                }
            }
        }
        .listRowBackground(StudentDetailSectionTint.account)
    }

    private var packageSection: some View {
        PackageListSection(
            student: student,
            onRequestDeduct: { package in
                packageToDeduct = package
            },
            onRequestReversePackage: { package in
                packagePendingReversal = package
                isConfirmingPackageReversal = true
            },
            onRequestReverseCharge: { package, charge in
                chargePackagePendingReversal = package
                chargePendingReversal = charge
                isConfirmingChargeReversal = true
            }
        )
    }

    private var videoSection: some View {
        VideoListSection(
            student: student,
            onCaptureVideo: { startVideoCapture() },
            onAddVideo: {
                newVideoDefaultDate = .now
                isAddingVideo = true
            },
            onPlayVideo: onPlayVideo
        )
    }

    private func recordSessionCharge(_ charge: LessonCharge, from package: LessonPackage) {
        guard charge.amount > 0, charge.amount <= package.remainingValue else { return }
        package.charges.append(charge)
        package.lessonsUsed += 1
        lastUndoAction = nil
        packageToDeduct = nil

        pendingLessonConfirmationCharge = charge
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard pendingLessonConfirmationCharge != nil else { return }
            isConfirmingLessonEmail = true
        }
    }

    private func prepareAccountStatementEmail(latestCharge: LessonCharge? = nil) {
        lessonEmailBody = StudentAccountStatementFormatter.message(for: student, latestCharge: latestCharge)

        if student.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lessonStatusMessage = String(localized: "Unable to prepare account statement because \(student.name) has no email address on file.")
            isShowingLessonStatus = true
            return
        }

        guard MFMailComposeViewController.canSendMail() else {
            lessonStatusMessage = String(localized: "This device cannot send email. Set up Mail on an iPhone and try again.")
            isShowingLessonStatus = true
            return
        }

        if latestCharge != nil {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                isShowingLessonEmailComposer = true
            }
        } else {
            isShowingLessonEmailComposer = true
        }
    }

    private var remainingCreditAfterPendingPackageDeletion: Decimal {
        let deletedCredit = packagesPendingDeletion.reduce(Decimal.zero) { $0 + $1.remainingValue }
        return max(student.remainingValue - deletedCredit, 0)
    }

    private var packageDeletionConfirmationMessage: String {
        let count = packagesPendingDeletion.count
        let packageWord = count == 1 ? "package" : "packages"
        return "Send \(student.name) a text message first, then delete \(count) \(packageWord)? \(CurrencyFormatter.string(from: remainingCreditAfterPendingPackageDeletion)) credit will remain."
    }

    private func stagePackagesForDeletion(_ packages: [LessonPackage]) {
        packagesPendingDeletion = packages
        isConfirmingPackageDeletion = !packagesPendingDeletion.isEmpty
    }

    private func preparePackageDeletionMessage() {
        let phoneNumber = student.phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        packageDeletionMessageRecipients = [phoneNumber]
        packageDeletionMessageBody = "Hi \(student.name), a package will be removed from your account. Your remaining credit is \(CurrencyFormatter.string(from: remainingCreditAfterPendingPackageDeletion))."

        guard !phoneNumber.isEmpty else {
            packagesPendingDeletion = []
            packageDeletionStatusMessage = "Package was not deleted because \(student.name) has no phone number on file."
            isShowingPackageDeletionStatus = true
            return
        }

        guard MFMessageComposeViewController.canSendText() else {
            packagesPendingDeletion = []
            packageDeletionStatusMessage = "Package was not deleted because this device cannot send text messages. Try on a physical iPhone."
            isShowingPackageDeletionStatus = true
            return
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !packagesPendingDeletion.isEmpty else { return }
            isShowingPackageDeletionMessageComposer = true
        }
    }

    private func handlePackageDeletionMessageResult(_ resultMessage: String?) {
        if resultMessage == "Text message sent." {
            commitPendingPackageDeletion()
            packageDeletionStatusMessage = "Text message sent and package deleted."
        } else if let resultMessage {
            packagesPendingDeletion = []
            packageDeletionStatusMessage = "\(resultMessage) Package was not deleted."
        } else {
            packagesPendingDeletion = []
            packageDeletionStatusMessage = "Text message cancelled. Package was not deleted."
        }

        isShowingPackageDeletionStatus = true
    }

    private func commitPendingPackageDeletion() {
        let deletedPackages = packagesPendingDeletion
        for package in packagesPendingDeletion {
            student.packages.removeAll { $0.persistentModelID == package.persistentModelID }
        }
        if !deletedPackages.isEmpty {
            lastUndoAction = .packageDeletion(deletedPackages)
        }
        packagesPendingDeletion = []
    }

    private func undoLastAction() {
        guard let lastUndoAction else { return }

        switch lastUndoAction {
        case .lessonCharge(let package, let charge):
            guard package.charges.contains(where: { $0.persistentModelID == charge.persistentModelID }) else {
                undoStatusMessage = "The session charge could not be reversed because it is no longer recorded."
                isShowingUndoStatus = true
                return
            }
            package.charges.removeAll { $0.persistentModelID == charge.persistentModelID }
            package.lessonsUsed = max(package.lessonsUsed - 1, 0)
            undoStatusMessage = "Session charge reversed. \(student.name) now has \(CurrencyFormatter.string(from: student.remainingValue)) remaining."

        case .packageDeletion(let packages):
            for package in packages where !student.packages.contains(where: { $0.persistentModelID == package.persistentModelID }) {
                student.packages.append(package)
            }
            undoStatusMessage = "Package delete reversed. \(student.name) now has \(CurrencyFormatter.string(from: student.remainingValue)) remaining."
        }

        self.lastUndoAction = nil
        isShowingUndoStatus = true
    }

    private func undoConfirmationMessage(for action: StudentUndoAction) -> String {
        switch action {
        case .lessonCharge(_, let charge):
            return "Reverse the lesson charge of \(CurrencyFormatter.string(from: charge.amount))? The credit will be restored."
        case .packageDeletion(let packages):
            return "Restore \(packages.count) deleted package record(s) to \(student.name)'s account?"
        }
    }

    private func reversePayment(_ package: LessonPackage) {
        guard student.packages.contains(where: { $0.persistentModelID == package.persistentModelID }) else {
            packagePendingReversal = nil
            isConfirmingFinalPackageReversal = false
            return
        }

        student.packages.removeAll { $0.persistentModelID == package.persistentModelID }
        packagePendingReversal = nil
        isConfirmingFinalPackageReversal = false
        lastUndoAction = nil
        undoStatusMessage = "Payment reversed. \(student.name) now has \(CurrencyFormatter.string(from: student.remainingValue)) remaining."
        promptForAccountUpdateEmail(
            String(localized: "The whole payment package has been deleted. Would you like to email the updated account statement to \(student.name)?")
        )
    }

    private func reverseLessonCharge(_ charge: LessonCharge) {
        guard let package = chargePackagePendingReversal,
              package.charges.contains(where: { $0.persistentModelID == charge.persistentModelID }) else {
            chargePendingReversal = nil
            chargePackagePendingReversal = nil
            isConfirmingFinalChargeReversal = false
            return
        }

        package.charges.removeAll { $0.persistentModelID == charge.persistentModelID }
        package.lessonsUsed = max(package.lessonsUsed - 1, 0)
        chargePendingReversal = nil
        chargePackagePendingReversal = nil
        isConfirmingFinalChargeReversal = false
        lastUndoAction = nil
        undoStatusMessage = "Lesson charge reversed. \(student.name) now has \(CurrencyFormatter.string(from: student.remainingValue)) remaining."
        promptForAccountUpdateEmail(
            String(localized: "The lesson fee has been restored. Would you like to email the updated account statement to \(student.name)?")
        )
    }

    private func promptForAccountUpdateEmail(_ message: String) {
        accountUpdateEmailPromptMessage = message
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard accountUpdateEmailPromptMessage != nil else { return }
            isConfirmingAccountUpdateEmail = true
        }
    }

    private func saveStudentDetails() {
        student.name = name
        student.phoneNumber = phoneNumber
        student.email = email
        student.birthday = birthday
        student.referralPersonName = referralPersonName
        student.yearsOfExperience = yearsOfExperience
        student.handicap = handicap
        student.golfGoal = golfGoal
        student.jobInfo = jobInfo
    }

    private func savePhoto(_ image: UIImage) {
        let maxDimension: CGFloat = 512
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height, 1.0)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        student.photoData = resized.jpegData(compressionQuality: 0.8)
    }

    private func startVideoCapture(for date: Date = .now) {
        if let issue = VideoCaptureReadiness.blockingIssue {
            videoCaptureError = issue
            isShowingVideoCaptureError = true
            return
        }

        captureVideoLessonDate = date
        processedCaptureURLs.removeAll()
        isCapturingSwingVideo = true
    }

    private func saveCapturedSwingVideo(from url: URL) {
        let sourceURL = url.standardizedFileURL
        guard processedCaptureURLs.insert(sourceURL).inserted else {
            print("DEBUG LessonVideo capture ignored duplicate callback: \(sourceURL.path)")
            return
        }

        do {
            let savedURL = try VideoFileStore.copyVideo(from: url)
            guard !LessonVideoDisplayStore.containsVideo(in: student.videos, matchingFileURL: savedURL),
                  !LessonVideoDisplayStore.containsVideo(in: student.videos, matchingContentOf: savedURL) else {
                print("DEBUG LessonVideo capture ignored duplicate stored path: \(savedURL.path)")
                return
            }

            let video = LessonVideo(
                title: "Lesson Video — \(captureVideoLessonDate.formatted(date: .abbreviated, time: .omitted))",
                recordedAt: .now,
                fileURLString: VideoFileStore.persistedFileName(for: savedURL),
                lessonDate: captureVideoLessonDate
            )
            student.videos.append(video)
            Task {
                await VideoFileStore.logVideoImport(url: savedURL, source: "camera")
            }
        } catch {
            print("DEBUG LessonVideo capture import failed: fileURL=\(sourceURL.path) error=\(error.localizedDescription)")
            videoCaptureError = error.localizedDescription
            isShowingVideoCaptureError = true
        }
    }
}

struct PackageListSection: View {
    @Bindable var student: Student
    let onRequestDeduct: (LessonPackage) -> Void
    let onRequestReversePackage: (LessonPackage) -> Void
    let onRequestReverseCharge: (LessonPackage, LessonCharge) -> Void

    var sortedPackages: [LessonPackage] {
        student.packages.sorted { $0.purchaseDate > $1.purchaseDate }
    }

    var body: some View {
        Section("Packages") {
            if sortedPackages.isEmpty {
                Text("No packages recorded")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedPackages) { package in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(package.packageType.localizedName)
                                .font(.headline)
                            Spacer()
                            Text("Balance: \(CurrencyFormatter.string(from: package.remainingValue))")
                                .font(.subheadline.weight(.semibold))
                        }

                        ProgressView(
                            value: NSDecimalNumber(decimal: package.amountDeducted).doubleValue,
                            total: max(NSDecimalNumber(decimal: package.totalPaid).doubleValue, 1)
                        )

                        HStack {
                            Text("Paid \(CurrencyFormatter.string(from: package.totalPaid))")
                            Spacer()
                            Text("Used \(CurrencyFormatter.string(from: package.amountDeducted))")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if let paymentMethod = package.paymentMethod {
                            Label(paymentMethod.localizedName, systemImage: "creditcard")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if !package.charges.isEmpty {
                            ForEach(package.charges.sorted { $0.chargedAt > $1.chargedAt }) { charge in
                                HStack {
                                    Text(charge.chargedAt, format: .dateTime.month().day())
                                    Text("\(charge.durationMinutes) min")
                                    Text("\(charge.participantCount) player(s)")
                                    Spacer()
                                    Text(CurrencyFormatter.string(from: charge.amount))
                                    Button {
                                        onRequestReverseCharge(package, charge)
                                    } label: {
                                        Image(systemName: "arrow.uturn.backward.circle")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(.red)
                                    .accessibilityLabel("Restore Deducted Lesson Fee")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }

                        Button {
                            onRequestDeduct(package)
                        } label: {
                            Label("Record Lesson Fee", systemImage: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .disabled(package.remainingValue <= 0)

                        HStack {
                            Spacer()
                            Button(role: .destructive) {
                                onRequestReversePackage(package)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Delete Payment Package")
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .listRowBackground(StudentDetailSectionTint.packages)
    }
}

struct LogSessionChargeView: View {
    @Environment(\.dismiss) private var dismiss
    let package: LessonPackage
    let onSave: (LessonCharge) -> Void
    @State private var chargedAt = Date.now
    @State private var durationMinutes = 60
    @State private var participantCount = 1
    @State private var amount = 0.0
    @State private var notes = ""

    private var decimalAmount: Decimal {
        Decimal(amount)
    }

    private var isValidAmount: Bool {
        decimalAmount > 0 && decimalAmount <= package.remainingValue
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Session Details") {
                    DatePicker("Lesson Date", selection: $chargedAt, displayedComponents: .date)
                    Stepper("Duration: \(durationMinutes) min", value: $durationMinutes, in: 15...240, step: 15)
                    Stepper("Players: \(participantCount)", value: $participantCount, in: 1...12)
                    TextField(
                        "Charge Amount",
                        value: $amount,
                        format: .currency(code: Locale.current.currency?.identifier ?? "USD")
                    )
                    .keyboardType(.decimalPad)
                    TextField("Charge notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section("Package Balance") {
                    LabeledContent("Available Credit", value: CurrencyFormatter.string(from: package.remainingValue))
                    if amount > 0 {
                        LabeledContent(
                            "Balance After Charge",
                            value: CurrencyFormatter.string(from: max(package.remainingValue - decimalAmount, 0))
                        )
                    }
                    if amount > 0 && !isValidAmount {
                        Text("The charge must be greater than zero and cannot exceed the available credit.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Record Lesson Fee")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let charge = LessonCharge(
                            chargedAt: chargedAt,
                            durationMinutes: durationMinutes,
                            participantCount: participantCount,
                            amount: decimalAmount,
                            notes: notes
                        )
                        onSave(charge)
                        dismiss()
                    }
                    .disabled(!isValidAmount)
                }
            }
        }
    }
}

struct LessonListSection: View {
    @Bindable var student: Student
    @State private var lessonForCalendar: LessonAppointment?

    var sortedLessons: [LessonAppointment] {
        student.lessons.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    var body: some View {
        Section("Lessons") {
            if sortedLessons.isEmpty {
                Text("No lessons scheduled")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedLessons) { lesson in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(lesson.title)
                                    .font(.headline)
                                Text(lesson.scheduledAt, format: .dateTime.weekday(.abbreviated).month().day().hour().minute())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("Done", isOn: Binding(
                                get: { lesson.isCompleted },
                                set: { lesson.isCompleted = $0 }
                            ))
                            .labelsHidden()
                        }

                        if !lesson.location.isEmpty {
                            Label(lesson.location, systemImage: "mappin.and.ellipse")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Label(lesson.reminderLeadTime.rawValue, systemImage: "bell")
                            Spacer()
                            Button {
                                lessonForCalendar = lesson
                            } label: {
                                Label("Calendar", systemImage: "calendar.badge.plus")
                            }
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 6)
                }
                .onDelete { offsets in
                    for index in offsets {
                        student.lessons.removeAll { $0.persistentModelID == sortedLessons[index].persistentModelID }
                    }
                }
            }
        }
        .listRowBackground(StudentDetailSectionTint.lessons)
        .sheet(item: $lessonForCalendar) { lesson in
            CalendarEventEditor(student: student, lesson: lesson)
        }
    }
}

struct VideoListSection: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var student: Student
    let onCaptureVideo: () -> Void
    let onAddVideo: () -> Void
    let onPlayVideo: (LessonVideo, Student) -> Void
    @State private var selectedVideoForEditing: LessonVideo?

    var sortedVideos: [LessonVideo] {
        LessonVideoDisplayStore.uniqueVideos(in: student.videos)
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    var lessonGroups: [LessonVideoGroup] {
        let groupedVideos = Dictionary(grouping: sortedVideos) { video in
            Calendar.current.startOfDay(for: video.lessonDate ?? video.recordedAt)
        }

        return groupedVideos
            .map { LessonVideoGroup(date: $0.key, videos: $0.value.sorted { $0.recordedAt > $1.recordedAt }) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        Section("Lesson Progress Videos") {
            Button(action: onCaptureVideo) {
                Label("Capture Swing Video", systemImage: "camera")
            }

            Button(action: onAddVideo) {
                Label("Import / Add Video", systemImage: "video.badge.plus")
            }

            if sortedVideos.isEmpty {
                Text("No swing videos saved")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(lessonGroups) { group in
                    LessonVideoGroupHeader(group: group, previousGroup: previousLessonGroup(before: group))

                    ForEach(group.videos) { video in
                        LessonVideoRow(
                            video: video,
                            defaultFocusNotes: "",
                            defaultProblemNotes: "",
                            onPlay: { openVideo(video) },
                            onEdit: { selectedVideoForEditing = video }
                        )
                    }
                    .onDelete { offsets in
                        deleteVideos(at: offsets, in: group)
                    }
                }
            }
        }
        .listRowBackground(StudentDetailSectionTint.videos)
        .sheet(item: $selectedVideoForEditing) { video in
            EditVideoView(video: video)
        }
    }

    private func previousLessonGroup(before group: LessonVideoGroup) -> LessonVideoGroup? {
        lessonGroups.first { $0.date < group.date }
    }

    private func deleteVideos(at offsets: IndexSet, in group: LessonVideoGroup) {
        for index in offsets {
            deleteVideo(group.videos[index])
        }
    }

    private func openVideo(_ video: LessonVideo) {
        guard video.fileURL != nil else {
            print("DEBUG VideoListSection selectedVideo ignored missing file: \(video.title)")
            return
        }

        print("DEBUG VideoListSection requested selectedVideo: \(video.title)")
        onPlayVideo(video, student)
    }

    private func deleteVideo(_ video: LessonVideo) {
        selectedVideoForEditing = nil
        VideoFileStore.deleteStoredVideoFile(for: video)
        student.videos.removeAll { $0.persistentModelID == video.persistentModelID }
        modelContext.delete(video)
    }
}

struct CoachAnalysisVideoSection: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var student: Student
    let onPlayCoachAnalysis: (CoachAnalysisVideo) -> Void

    var sortedAnalyses: [CoachAnalysisVideo] {
        student.coachAnalysisVideos.sorted { $0.recordedAt > $1.recordedAt }
    }

    var body: some View {
        Section("Coach Analysis Videos") {
            if sortedAnalyses.isEmpty {
                Text("No coach analysis videos saved")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedAnalyses) { analysis in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(analysis.title)
                                .font(.subheadline.weight(.semibold))
                            Text(analysis.recordedAt, format: .dateTime.month().day().year().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if analysis.fileURL == nil {
                                Text("Analysis not generated yet")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if let url = analysis.fileURL {
                            Button {
                                openAnalysis(analysis)
                            } label: {
                                Label("Play", systemImage: "play.circle")
                            }
                            .buttonStyle(.borderless)

                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .buttonStyle(.borderless)
                        } else {
                            Button {
                                openAnalysis(analysis)
                            } label: {
                                Label("Create Analysis", systemImage: "record.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        openAnalysis(analysis)
                    }
                }
                .onDelete(perform: deleteAnalyses)
            }
        }
        .listRowBackground(StudentDetailSectionTint.coachAnalysis)
    }

    private func openAnalysis(_ analysis: CoachAnalysisVideo) {
        print("DEBUG CoachAnalysisVideoSection requested selectedCoachAnalysis: \(analysis.title)")
        onPlayCoachAnalysis(analysis)
    }

    private func deleteAnalyses(at offsets: IndexSet) {
        for index in offsets {
            let analysis = sortedAnalyses[index]
            if let url = analysis.fileURL {
                try? FileManager.default.removeItem(at: url)
            }
            student.coachAnalysisVideos.removeAll { $0.persistentModelID == analysis.persistentModelID }
            modelContext.delete(analysis)
        }
    }
}

struct CoachAnalysisView: View {
    @Environment(\.dismiss) private var dismiss
    let analysis: CoachAnalysisVideo
    @State private var player: AVPlayer?
    @State private var currentTime = 0.0
    @State private var duration = 0.0
    @State private var frameRate: Float = 30
    @State private var playbackRate: Float = 1.0
    @State private var isPlaying = false
    @State private var isScrubbing = false
    @State private var timeObserver: Any?
    @State private var isShowingCreateGuidance = false
    @State private var isDrawingMode = false
    @State private var selectedDrawingTool = SwingDrawingTool.line
    @State private var selectedDrawingColor = SwingDrawingColor.yellow
    @State private var strokes: [SwingAnalysisStroke] = []
    @State private var currentStroke: SwingAnalysisStroke?
    @State private var zoomScale: CGFloat = 1
    @State private var zoomStartScale: CGFloat = 1
    @State private var zoomOffset = CGSize.zero
    @State private var zoomStartOffset = CGSize.zero
    @State private var isSavingToPhotos = false
    @State private var saveStatus: VideoSaveStatus?
    @State private var isShowingSaveStatus = false
    @State private var isShowingAnalysisInfo = false

    init(analysis: CoachAnalysisVideo) {
        self.analysis = analysis
        _player = State(initialValue: analysis.fileURL.map { AVPlayer(url: $0) })
    }

    var body: some View {
        NavigationStack {
            Group {
                if let player {
                    GeometryReader { proxy in
                        ZStack(alignment: .top) {
                            ZStack {
                                ControlledVideoPlayer(player: player, showsPlaybackControls: !isDrawingMode)
                                    .background(.black)

                                SwingDrawingOverlay(
                                    strokes: $strokes,
                                    currentStroke: $currentStroke,
                                    selectedTool: $selectedDrawingTool,
                                    selectedColor: $selectedDrawingColor,
                                    isDrawingEnabled: isDrawingMode,
                                    onUndo: undoLastStroke,
                                    onZoomBegan: beginZoom,
                                    onZoomChanged: { relativeScale in
                                        updateZoom(relativeScale: relativeScale, in: proxy.size)
                                    },
                                    onZoomEnded: endZoom,
                                    onZoomPanBegan: beginZoomPan,
                                    onZoomPanChanged: { translation in
                                        updateZoomPan(translation: translation, in: proxy.size)
                                    }
                                )
                            }
                            .scaleEffect(zoomScale)
                            .offset(zoomOffset)
                            .contentShape(Rectangle())
                            .gesture(coachAnalysisTransformGesture(in: proxy.size), isEnabled: !isDrawingMode)
                            .onTapGesture(count: 2) {
                                resetZoom()
                            }

                            HStack(alignment: .top) {
                                if isDrawingMode {
                                    DrawingToolPalette(
                                        selectedTool: $selectedDrawingTool,
                                        selectedColor: $selectedDrawingColor,
                                        canUndo: !strokes.isEmpty,
                                        onUndo: undoLastStroke
                                    )
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                        }
                        .clipped()
                    }
                } else {
                    ContentUnavailableView {
                        Label("Analysis not generated yet", systemImage: "waveform.path.ecg")
                    } description: {
                        Text("Create a coach analysis recording from the Swing Comparison screen or an individual swing video.")
                    } actions: {
                        Button {
                            isShowingCreateGuidance = true
                        } label: {
                            Label("Create Analysis", systemImage: "record.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle(analysis.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        player?.pause()
                        dismiss()
                    }
                }

                if let url = analysis.fileURL {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: url) {
                            Label("Send", systemImage: "square.and.arrow.up")
                        }
                    }

                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                isDrawingMode.toggle()
                                if isDrawingMode {
                                    player?.pause()
                                    isPlaying = false
                                }
                            } label: {
                                Label(isDrawingMode ? "Stop Drawing" : "Draw Lines", systemImage: "pencil.and.outline")
                            }

                            Button {
                                undoLastStroke()
                            } label: {
                                Label("Undo Last Drawing", systemImage: "arrow.uturn.backward")
                            }
                            .disabled(strokes.isEmpty)

                            Button(role: .destructive) {
                                clearStrokes()
                            } label: {
                                Label("Clear Lines", systemImage: "trash")
                            }
                            .disabled(strokes.isEmpty)

                            if hasAnalysisNotes {
                                Button {
                                    isShowingAnalysisInfo = true
                                } label: {
                                    Label("Info", systemImage: "info.circle")
                                }
                            }

                            Button {
                                saveVideoToPhotos(url)
                            } label: {
                                Label("Save to Photos", systemImage: "photo.badge.plus")
                            }
                            .disabled(isSavingToPhotos)
                        } label: {
                            if isSavingToPhotos {
                                ProgressView()
                            } else {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if player != nil {
                    simplePlaybackControls
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.regularMaterial)
                }
            }
            .onAppear {
                prepareForPlayback()
            }
            .onDisappear {
                player?.pause()
                removeTimeObserver()
            }
            .alert("Create Analysis", isPresented: $isShowingCreateGuidance) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Open Swing Comparison, tap Coach Analysis, then stop the recording to generate a playable analysis video.")
            }
            .alert(saveStatus?.title ?? "Save Video", isPresented: $isShowingSaveStatus) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveStatus?.message ?? "")
            }
            .sheet(isPresented: $isShowingAnalysisInfo) {
                NavigationStack {
                    ScrollView {
                        Text(analysisNotes)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .navigationTitle("Analysis Info")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                isShowingAnalysisInfo = false
                            }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private var analysisNotes: String {
        analysis.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasAnalysisNotes: Bool {
        !analysisNotes.isEmpty
    }

    private var simplePlaybackControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    togglePlayback()
                } label: {
                    Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                Text("\(timeString(currentTime)) / \(timeString(duration))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { currentTime },
                    set: { value in
                        currentTime = min(max(value, 0), duration)
                    }
                ),
                in: 0...max(duration, 0.1),
                onEditingChanged: { editing in
                    if editing {
                        isScrubbing = true
                        player?.pause()
                        isPlaying = false
                    } else {
                        isScrubbing = false
                        seek(to: currentTime)
                    }
                }
            )
        }
    }

    private func prepareForPlayback() {
        Task { @MainActor in
            guard let player else { return }
            player.pause()
            guard await VideoPlaybackReadiness.waitUntilReady(player.currentItem) else { return }
            await loadPlaybackMetadata()
            await player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            currentTime = 0
            configureTimeObserver()
        }
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    private func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        player?.rate = rate
        isPlaying = rate > 0
    }

    private func seek(to seconds: Double) {
        let targetSeconds = max(0, min(seconds, duration))
        currentTime = targetSeconds
        player?.seek(to: CMTime(seconds: targetSeconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func stepFrame(direction: Int) {
        player?.pause()
        isPlaying = false
        let frameStep = 1 / max(Double(frameRate), 1)
        seek(to: currentTime + (Double(direction) * frameStep))
    }

    private func configureTimeObserver() {
        removeTimeObserver()
        guard let player else { return }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600), queue: .main) { time in
            guard !isScrubbing else { return }
            let seconds = time.seconds
            if seconds.isFinite {
                currentTime = max(0, min(seconds, duration))
            }
            isPlaying = player.rate != 0
        }
    }

    private func removeTimeObserver() {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    @MainActor
    private func loadPlaybackMetadata() async {
        guard let url = analysis.fileURL else { return }
        let asset = AVURLAsset(url: url)
        let loadedDuration = (try? await asset.load(.duration).seconds) ?? 0
        duration = loadedDuration.isFinite ? max(loadedDuration, 0) : 0

        let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        if let track = tracks.first {
            let loadedFrameRate = (try? await track.load(.nominalFrameRate)) ?? 0
            if loadedFrameRate.isFinite, loadedFrameRate > 0 {
                frameRate = loadedFrameRate
            }
        }
    }

    private func undoLastStroke() {
        _ = strokes.popLast()
    }

    private func clearStrokes() {
        strokes.removeAll()
        currentStroke = nil
    }

    private func beginZoom() {
        zoomStartScale = zoomScale
    }

    private func updateZoom(relativeScale: CGFloat, in size: CGSize) {
        zoomScale = min(max(zoomStartScale * relativeScale, 1), 5)
        zoomOffset = clampedZoomOffset(zoomOffset, scale: zoomScale, in: size)
    }

    private func endZoom() {
        commitZoomTransform()
    }

    private func beginZoomPan() {
        zoomStartOffset = zoomOffset
    }

    private func updateZoomPan(translation: CGSize, in size: CGSize) {
        guard zoomScale > 1 else {
            zoomOffset = .zero
            zoomStartOffset = .zero
            return
        }
        let proposedOffset = CGSize(
            width: zoomStartOffset.width + translation.width,
            height: zoomStartOffset.height + translation.height
        )
        zoomOffset = clampedZoomOffset(proposedOffset, scale: zoomScale, in: size)
    }

    private func coachAnalysisTransformGesture(in size: CGSize) -> some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    updateZoom(relativeScale: value, in: size)
                }
                .onEnded { _ in
                    commitZoomTransform()
                },
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    updateZoomPan(translation: value.translation, in: size)
                }
                .onEnded { _ in
                    commitZoomTransform()
                }
        )
    }

    private func commitZoomTransform() {
        zoomScale = min(max(zoomScale, 1), 5)
        zoomOffset = zoomScale <= 1 ? .zero : zoomOffset
        zoomStartScale = zoomScale
        zoomStartOffset = zoomOffset
    }

    private func resetZoom() {
        zoomScale = 1
        zoomStartScale = 1
        zoomOffset = .zero
        zoomStartOffset = .zero
    }

    private func clampedZoomOffset(_ offset: CGSize, scale: CGFloat, in size: CGSize) -> CGSize {
        guard scale > 1 else { return .zero }
        let horizontalLimit = (size.width * (scale - 1)) / 2
        let verticalLimit = (size.height * (scale - 1)) / 2
        return CGSize(
            width: min(max(offset.width, -horizontalLimit), horizontalLimit),
            height: min(max(offset.height, -verticalLimit), verticalLimit)
        )
    }

    private func saveVideoToPhotos(_ url: URL) {
        isSavingToPhotos = true
        Task {
            do {
                try await PhotoLibraryVideoSaver.saveVideoToCameraRoll(url: url)
                saveStatus = .success
            } catch {
                saveStatus = .failure(error.localizedDescription)
            }
            isSavingToPhotos = false
            isShowingSaveStatus = true
        }
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let totalSeconds = max(Int(seconds), 0)
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }
}

enum VideoPlaybackReadiness {
    @MainActor
    static func waitUntilReady(_ item: AVPlayerItem?) async -> Bool {
        guard let item else { return false }

        switch item.status {
        case .readyToPlay:
            return true
        case .failed:
            return false
        case .unknown:
            return await withCheckedContinuation { continuation in
                var observation: NSKeyValueObservation?
                var didResume = false

                observation = item.observe(\.status, options: [.new]) { observedItem, _ in
                    guard observedItem.status == .readyToPlay || observedItem.status == .failed else {
                        return
                    }

                    guard !didResume else { return }
                    didResume = true
                    observation?.invalidate()
                    continuation.resume(returning: observedItem.status == .readyToPlay)
                }
            }
        @unknown default:
            return false
        }
    }
}

struct LessonVideoGroupHeader: View {
    let group: LessonVideoGroup
    let previousGroup: LessonVideoGroup?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.date, format: .dateTime.weekday(.abbreviated).month().day().year())
                    .font(.headline)
                Spacer()
                Text("\(group.videos.count) video\(group.videos.count == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let previousGroup {
                Label(
                    "Compare with \(previousGroup.date.formatted(date: .abbreviated, time: .omitted))",
                    systemImage: "arrow.left.arrow.right"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
        .listRowBackground(Color.clear)
    }
}

struct LessonVideoGroup: Identifiable {
    let date: Date
    let videos: [LessonVideo]

    var id: Date { date }
}

struct LessonVideoRow: View {
    let video: LessonVideo
    let defaultFocusNotes: String
    let defaultProblemNotes: String
    let onPlay: () -> Void
    let onEdit: () -> Void
    @State private var isSharing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onPlay) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.title3)
                        .foregroundStyle(video.fileURL == nil ? Color.secondary : Color.blue)
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(video.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(video.recordedAt, format: .dateTime.hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if video.fileURL == nil {
                            Label("Missing local video", systemImage: "exclamationmark.triangle")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .disabled(video.fileURL == nil)

            HStack(spacing: 8) {
                if video.fileURL != nil {
                    Button {
                        isSharing = true
                    } label: {
                        Label("Send", systemImage: "square.and.arrow.up")
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }

                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
                .font(.caption)
                .buttonStyle(.borderless)

                Spacer()
            }
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.85)

            VStack(alignment: .leading, spacing: 10) {
                ProgressNote(label: "Improving", text: firstNonEmpty(video.focusNotes, defaultFocusNotes))
                ProgressNote(label: "Problem", text: firstNonEmpty(video.problemNotes, defaultProblemNotes))
                ProgressNote(label: "Compare", text: video.comparisonNotes)
                ProgressNote(label: "Analysis", text: video.notes)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .sheet(isPresented: $isSharing) {
            VideoShareView(videoURL: video.fileURL, notesText: notesText)
        }
    }

    private var notesText: String {
        var parts: [String] = []
        let dateStr = video.recordedAt.formatted(date: .abbreviated, time: .shortened)
        parts.append("\(video.title) — \(dateStr)")
        if let focus = firstNonEmpty(video.focusNotes, defaultFocusNotes) {
            parts.append("Improving:\n\(focus)")
        }
        if let problem = firstNonEmpty(video.problemNotes, defaultProblemNotes) {
            parts.append("Problem Areas:\n\(problem)")
        }
        if let comparison = video.comparisonNotes, !comparison.isEmpty {
            parts.append("Comparison:\n\(comparison)")
        }
        if !video.notes.isEmpty {
            parts.append("Coach Notes:\n\(video.notes)")
        }
        return parts.joined(separator: "\n\n")
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        values.compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }.first
    }
}

struct SwingComparisonSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let student: Student
    let lessonDate: Date
    let sessionStateManager: SessionStateManager
    let restoreComparisonOnAppear: Bool
    @State private var beforeVideo: LessonVideo?
    @State private var afterVideo: LessonVideo?
    @State private var isOpeningRestoredComparison = false
    @State private var hasAttemptedComparisonRestoration = false
    @State private var selectedVideos: [LessonVideo] = []

    private var uniqueVideos: [LessonVideo] {
        LessonVideoDisplayStore.uniqueVideos(in: student.videos)
            .filter { $0.fileURL != nil }
            .sorted { ($0.lessonDate ?? $0.recordedAt) > ($1.lessonDate ?? $1.recordedAt) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerSection
                        videoGrid
                    }
                    .padding()
                }

                openComparisonBar
            }
            .navigationTitle("Compare Videos")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $isOpeningRestoredComparison) {
                if selectedVideos.count == 2,
                   let beforeVideo = selectedVideos.first,
                   let afterVideo = selectedVideos.last,
                   let beforeURL = beforeVideo.fileURL,
                   let afterURL = afterVideo.fileURL {
                    comparisonView(
                        beforeVideo: beforeVideo,
                        afterVideo: afterVideo,
                        beforeURL: beforeURL,
                        afterURL: afterURL,
                        restoredState: sessionStateManager.state
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                LessonVideoDisplayStore.removeDuplicatesIfNeeded(in: student, context: modelContext)
                await LessonVideoDisplayStore.logVideos(
                    rawVideos: student.videos.filter { $0.fileURL != nil },
                    uniqueVideos: uniqueVideos,
                    context: "Compare Videos"
                )
                restoreSavedComparisonIfNeeded()
            }
        }
    }

    private func comparisonView(
        beforeVideo: LessonVideo,
        afterVideo: LessonVideo,
        beforeURL: URL,
        afterURL: URL,
        restoredState: LastSessionState?
        ) -> some View {
        SwingComparisonView(
            beforeVideo: beforeVideo,
            afterVideo: afterVideo,
            beforeURL: beforeURL,
            afterURL: afterURL,
            student: student,
            sessionStateManager: sessionStateManager,
            restoredState: restoredState
        )
    }

    private func restoreSavedComparisonIfNeeded() {
        guard !hasAttemptedComparisonRestoration else { return }
        hasAttemptedComparisonRestoration = true

        guard restoreComparisonOnAppear,
              sessionStateManager.state.hasComparison,
              let before = uniqueVideos.first(where: {
                  sessionStateManager.matches($0, storedIdentifier: sessionStateManager.state.beforeComparisonVideoID)
              }),
              let after = uniqueVideos.first(where: {
                  sessionStateManager.matches($0, storedIdentifier: sessionStateManager.state.afterComparisonVideoID)
              }) else {
            return
        }

        selectedVideos = [before, after]
        isOpeningRestoredComparison = true
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select 2 videos to compare")
                .font(.title3.weight(.semibold))

            Text(selectionStatusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var videoGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            if uniqueVideos.isEmpty {
                Text("No saved lesson videos are available to compare.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(uniqueVideos, id: \.persistentModelID) { video in
                    ComparisonVideoThumbnailCard(
                        video: video,
                        selectionNumber: selectionNumber(for: video)
                    ) {
                        toggleSelection(for: video)
                    }
                }
            }
        }
    }

    private var openComparisonBar: some View {
        VStack(spacing: 8) {
            if selectedVideos.count == 2,
               let beforeVideo = selectedVideos.first,
               let afterVideo = selectedVideos.last,
               let beforeURL = beforeVideo.fileURL,
               let afterURL = afterVideo.fileURL {
                NavigationLink {
                    comparisonView(
                        beforeVideo: beforeVideo,
                        afterVideo: afterVideo,
                        beforeURL: beforeURL,
                        afterURL: afterURL,
                        restoredState: nil
                    )
                } label: {
                    Label("Open Comparison", systemImage: "play.rectangle.on.rectangle")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                } label: {
                    Label("Open Comparison", systemImage: "play.rectangle.on.rectangle")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.borderedProminent)
                .disabled(true)

                Text("Tap two different video thumbnails first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.bar)
    }

    private var selectionStatusText: String {
        switch selectedVideos.count {
        case 0:
            return "Tap the first video."
        case 1:
            return "Video 1 selected. Tap the second video."
        default:
            return "Video 1 becomes Before. Video 2 becomes After."
        }
    }

    private func selectionNumber(for video: LessonVideo) -> Int? {
        selectedVideos.firstIndex { $0.persistentModelID == video.persistentModelID }.map { $0 + 1 }
    }

    private func toggleSelection(for video: LessonVideo) {
        if let index = selectedVideos.firstIndex(where: { $0.persistentModelID == video.persistentModelID }) {
            selectedVideos.remove(at: index)
        } else if selectedVideos.count < 2 {
            selectedVideos.append(video)
        } else {
            selectedVideos[1] = video
        }
    }
}

private struct ComparisonVideoThumbnailCard: View {
    let video: LessonVideo
    let selectionNumber: Int?
    let onTap: () -> Void
    @State private var thumbnail: UIImage?
    @State private var durationText = "--:--"

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    thumbnailView

                    if let selectionNumber {
                        Text("\(selectionNumber)")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(.blue, in: Circle())
                            .padding(8)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(video.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(video.lessonDate ?? video.recordedAt, format: .dateTime.month().day().year())
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(durationText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selectionNumber == nil ? .clear : .blue, lineWidth: 3)
            }
        }
        .buttonStyle(.plain)
        .task(id: video.persistentModelID) {
            await loadThumbnail()
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.tertiarySystemFill))
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    Image(systemName: "video.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
        }
    }

    @MainActor
    private func loadThumbnail() async {
        guard let url = video.fileURL else { return }
        let asset = AVURLAsset(url: url)

        if let duration = try? await asset.load(.duration).seconds,
           duration.isFinite {
            durationText = formattedDuration(duration)
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)

        do {
            let image = try generator.copyCGImage(at: .zero, actualTime: nil)
            thumbnail = UIImage(cgImage: image)
        } catch {
            print("DEBUG Compare thumbnail failed: \(url.path) \(error.localizedDescription)")
        }
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let totalSeconds = max(Int(seconds.rounded()), 0)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private enum ComparisonPane: String, CaseIterable, Identifiable {
    case before
    case after

    var id: Self { self }
    var label: LocalizedStringKey { self == .before ? "Before" : "After" }
}

struct SwingComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    let beforeVideo: LessonVideo
    let afterVideo: LessonVideo
    private let beforeURL: URL
    private let afterURL: URL
    private let student: Student?
    private let sessionStateManager: SessionStateManager

    @State private var beforePlayer: AVPlayer
    @State private var afterPlayer: AVPlayer
    @State private var beforeDuration = 0.0
    @State private var afterDuration = 0.0
    @State private var beforeFPS = 30.0
    @State private var afterFPS = 30.0
    @State private var beforeAspectRatio: CGFloat = 9.0 / 16.0
    @State private var afterAspectRatio: CGFloat = 9.0 / 16.0
    @State private var beforeFrame = 0
    @State private var afterFrame = 0
    @State private var beforeProgress = 0.0
    @State private var afterProgress = 0.0
    @State private var playbackRate: Float = 1.0
    @State private var isPlaying = false
    @State private var isBeforeScrubbing = false
    @State private var isAfterScrubbing = false
    @State private var isSeekingBefore = false
    @State private var isSeekingAfter = false
    @State private var chasedBeforeSeconds: Double?
    @State private var chasedAfterSeconds: Double?
    @State private var beforeSeekTask: Task<Void, Never>?
    @State private var afterSeekTask: Task<Void, Never>?
    @State private var beforeTimeObserver: Any?
    @State private var afterTimeObserver: Any?
    @State private var focusedPane: ComparisonPane = .before
    @State private var isDrawingEnabled = false
    @State private var drawingTool: SwingDrawingTool = .line
    @State private var drawingColor: SwingDrawingColor = .yellow
    @State private var beforeStrokes: [SwingAnalysisStroke] = []
    @State private var afterStrokes: [SwingAnalysisStroke] = []
    @State private var beforeCurrentStroke: SwingAnalysisStroke?
    @State private var afterCurrentStroke: SwingAnalysisStroke?
    @State private var beforeZoomScale: CGFloat = 1
    @State private var afterZoomScale: CGFloat = 1
    @State private var beforeZoomOffset: CGSize = .zero
    @State private var afterZoomOffset: CGSize = .zero
    @State private var beforeLastZoomScale: CGFloat = 1
    @State private var afterLastZoomScale: CGFloat = 1
    @State private var beforeLastZoomOffset: CGSize = .zero
    @State private var afterLastZoomOffset: CGSize = .zero
    @State private var coachAnalysisRecorder = CoachAnalysisRecorder()
    @State private var isRecordingCoachAnalysis = false
    @State private var coachAnalysisStatus: VideoSaveStatus?
    @State private var isShowingCoachAnalysisStatus = false

    init(
        beforeVideo: LessonVideo,
        afterVideo: LessonVideo,
        beforeURL: URL,
        afterURL: URL,
        student: Student? = nil,
        sessionStateManager: SessionStateManager,
        restoredState: LastSessionState? = nil
    ) {
        self.beforeVideo = beforeVideo
        self.afterVideo = afterVideo
        self.beforeURL = beforeURL
        self.afterURL = afterURL
        self.student = student
        self.sessionStateManager = sessionStateManager
        _beforePlayer = State(initialValue: AVPlayer(url: beforeURL))
        _afterPlayer = State(initialValue: AVPlayer(url: afterURL))
        _beforeProgress = State(initialValue: restoredState?.beforeVideoProgress ?? 0)
        _afterProgress = State(initialValue: restoredState?.afterVideoProgress ?? 0)
        _playbackRate = State(initialValue: restoredState?.playbackSpeed ?? 1.0)
    }

    var body: some View {
        GeometryReader { geometry in
            let isPad = UIDevice.current.userInterfaceIdiom == .pad
            let isLandscape = geometry.size.width > geometry.size.height
            let contentSize = CGSize(
                width: geometry.size.width,
                height: max(0, geometry.size.height - geometry.safeAreaInsets.top)
            )
            ZStack(alignment: .topLeading) {
                if isLandscape {
                    landscapeContent(size: contentSize)
                } else {
                    portraitContent(size: contentSize, isPad: isPad)
                }

                floatingBackButton
                floatingMoreControlsButton
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadPlaybackMetadata()
            let beforeSeconds = min(beforeProgress * beforeDuration, beforeDuration)
            let afterSeconds = min(afterProgress * afterDuration, afterDuration)
            beforeFrame = frame(for: beforeSeconds, pane: .before)
            afterFrame = frame(for: afterSeconds, pane: .after)
            await seek(beforePlayer, to: beforeSeconds)
            await seek(afterPlayer, to: afterSeconds)
            updateProgress(for: .before, seconds: beforeSeconds)
            updateProgress(for: .after, seconds: afterSeconds)
            addTimeObservers()
            saveComparisonState()
        }
        .onDisappear {
            beforeSeekTask?.cancel()
            afterSeekTask?.cancel()
            saveComparisonState()
            pauseBoth()
            removeTimeObservers()
            if isRecordingCoachAnalysis {
                stopCoachAnalysisRecording()
            }
        }
        .onChange(of: playbackRate) { _, _ in
            saveComparisonState()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                saveComparisonState()
            }
        }
        .alert(coachAnalysisStatus?.title ?? "Coach Analysis", isPresented: $isShowingCoachAnalysisStatus) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(coachAnalysisStatus?.message ?? "")
        }
    }

    private func portraitContent(size: CGSize, isPad: Bool) -> some View {
        comparisonContent(size: size, isLandscape: false, isSideBySide: isPad)
            .padding(.top, 4)
            .background(Color(.systemBackground))
    }

    private func landscapeContent(size: CGSize) -> some View {
        comparisonContent(size: size, isLandscape: true, isSideBySide: true)
        .background(Color(.systemBackground))
        .safeAreaPadding(.top, 4)
    }

    private var floatingBackButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(.ultraThinMaterial, in: Circle())
        .shadow(color: .black.opacity(0.16), radius: 8, y: 2)
        .padding(.leading, 12)
        .padding(.top, 8)
        .accessibilityLabel("Back")
    }

    private var floatingMoreControlsButton: some View {
        HStack {
            Spacer()
            Menu {
                Button {
                    isDrawingEnabled.toggle()
                } label: {
                    Label(isDrawingEnabled ? "Stop Drawing" : "Draw Mode", systemImage: isDrawingEnabled ? "pencil.slash" : "pencil.tip")
                }

                Button {
                    drawingTool = .line
                    isDrawingEnabled = true
                } label: {
                    Label(drawingTool == .line ? "Line Tool Selected" : "Line Tool", systemImage: drawingTool == .line ? "checkmark" : "line.diagonal")
                }

                Button {
                    drawingTool = .circle
                    isDrawingEnabled = true
                } label: {
                    Label(drawingTool == .circle ? "Circle Tool Selected" : "Circle Tool", systemImage: drawingTool == .circle ? "checkmark" : "circle")
                }

                Button {
                    undoDrawing()
                } label: {
                    Label("Undo Last Drawing", systemImage: "arrow.uturn.backward")
                }
                .disabled(activeStrokes.isEmpty)

                Button(role: .destructive) {
                    clearDrawings()
                } label: {
                    Label("Clear Drawing", systemImage: "trash")
                }
                .disabled(activeStrokes.isEmpty)

                Divider()

                Button {
                    toggleCoachAnalysisRecording()
                } label: {
                    Label(coachAnalysisButtonTitle, systemImage: isRecordingCoachAnalysis ? "stop.circle.fill" : "waveform.path.ecg")
                }
                .disabled(coachAnalysisRecorder.isRecording && !isRecordingCoachAnalysis)

                Divider()

                Button {
                    playBoth()
                } label: {
                    Label("Play All", systemImage: "play.fill")
                }
                .disabled(isSeekingBefore || isSeekingAfter)

                Button {
                    pauseBoth()
                } label: {
                    Label("Pause All", systemImage: "pause.fill")
                }

                Menu {
                    speedButton(title: "0.5x", rate: 0.5)
                    speedButton(title: "1.0x", rate: 1.0)
                } label: {
                    Label("Speed \(playbackRate, specifier: "%.1f")x", systemImage: "speedometer")
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .background(.ultraThinMaterial, in: Circle())
            .shadow(color: .black.opacity(0.16), radius: 8, y: 2)
            .accessibilityLabel("More Controls")
        }
        .padding(.trailing, 12)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func comparisonContent(size: CGSize, isLandscape: Bool, isSideBySide: Bool) -> some View {
        let maxVideoHeight = videoSurfaceHeight(
            for: size,
            isLandscape: isLandscape,
            isSideBySide: isSideBySide
        )

        if isSideBySide {
            HStack(spacing: isLandscape ? 6 : 8) {
                beforePane(maxVideoHeight: maxVideoHeight, compact: true)
                afterPane(maxVideoHeight: maxVideoHeight, compact: true)
            }
            .padding(.horizontal, isLandscape ? 6 : 6)
            .padding(.top, isLandscape ? 6 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 6) {
                beforePane(maxVideoHeight: maxVideoHeight, compact: true)
                afterPane(maxVideoHeight: maxVideoHeight, compact: true)
            }
            .padding(.horizontal, 6)
            .frame(maxHeight: .infinity)
        }
    }

    private func videoSurfaceHeight(for size: CGSize, isLandscape: Bool, isSideBySide: Bool) -> CGFloat {
        let paneChromeHeight: CGFloat = 76
        let topReserve: CGFloat = isLandscape ? 8 : 12

        if isLandscape {
            return max(96, size.height - paneChromeHeight - topReserve)
        }

        if isSideBySide {
            return max(150, size.height - paneChromeHeight - topReserve)
        }

        let interPaneSpacing: CGFloat = 6
        let availableVideoHeight = size.height - (paneChromeHeight * 2) - interPaneSpacing - topReserve
        return max(60, availableVideoHeight / 2)
    }

    private func beforePane(maxVideoHeight: CGFloat, compact: Bool) -> some View {
        ComparisonVideoPane(
            title: "Before",
            video: beforeVideo,
            player: beforePlayer,
            duration: beforeDuration,
            progress: $beforeProgress,
            strokes: $beforeStrokes,
            currentStroke: $beforeCurrentStroke,
            isDrawingEnabled: isDrawingEnabled,
            drawingTool: drawingTool,
            drawingColor: drawingColor,
            isSelectedForDrawing: focusedPane == .before,
            videoAspectRatio: beforeAspectRatio,
            maxVideoHeight: maxVideoHeight,
            compact: compact,
            frameLabel: "Before Frame",
            currentFrame: beforeFrame,
            totalFrames: totalFrames(for: .before),
            zoomScale: $beforeZoomScale,
            zoomOffset: $beforeZoomOffset,
            lastZoomScale: $beforeLastZoomScale,
            lastZoomOffset: $beforeLastZoomOffset,
            onSelect: { focusedPane = .before },
            onFrameRequested: { requestFrameSeek(for: .before, to: $0) },
            onScrubbingChanged: { editing in
                isBeforeScrubbing = editing
                handleScrubbingChange(editing)
            }
        )
    }

    private func afterPane(maxVideoHeight: CGFloat, compact: Bool) -> some View {
        ComparisonVideoPane(
            title: "After",
            video: afterVideo,
            player: afterPlayer,
            duration: afterDuration,
            progress: $afterProgress,
            strokes: $afterStrokes,
            currentStroke: $afterCurrentStroke,
            isDrawingEnabled: isDrawingEnabled,
            drawingTool: drawingTool,
            drawingColor: drawingColor,
            isSelectedForDrawing: focusedPane == .after,
            videoAspectRatio: afterAspectRatio,
            maxVideoHeight: maxVideoHeight,
            compact: compact,
            frameLabel: "After Frame",
            currentFrame: afterFrame,
            totalFrames: totalFrames(for: .after),
            zoomScale: $afterZoomScale,
            zoomOffset: $afterZoomOffset,
            lastZoomScale: $afterLastZoomScale,
            lastZoomOffset: $afterLastZoomOffset,
            onSelect: { focusedPane = .after },
            onFrameRequested: { requestFrameSeek(for: .after, to: $0) },
            onScrubbingChanged: { editing in
                isAfterScrubbing = editing
                handleScrubbingChange(editing)
            }
        )
    }

    private var coachAnalysisButtonTitle: LocalizedStringKey {
        if isRecordingCoachAnalysis {
            return "Stop"
        }
        return horizontalSizeClass == .compact ? "Coach" : "Coach Analysis"
    }

    private var speedMenu: some View {
        Menu {
            speedButton(title: "0.5x", rate: 0.5)
            speedButton(title: "1.0x", rate: 1.0)
        } label: {
            Label("\(playbackRate, specifier: "%.1f")x", systemImage: "speedometer")
        }
        .buttonStyle(.bordered)
    }

    private func speedButton(title: LocalizedStringKey, rate: Float) -> some View {
        Button {
            playbackRate = rate
            guard isPlaying else { return }
            beforePlayer.rate = rate
            afterPlayer.rate = rate
        } label: {
            if playbackRate == rate {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private var activeStrokes: [SwingAnalysisStroke] {
        focusedPane == .before ? beforeStrokes : afterStrokes
    }

    private func drawingToolButton(_ title: LocalizedStringKey, tool: SwingDrawingTool, icon: String) -> some View {
        Button {
            drawingTool = tool
        } label: {
            Label(title, systemImage: icon)
        }
        .buttonStyle(.bordered)
        .tint(drawingTool == tool ? .purple : .secondary)
    }

    private func undoDrawing() {
        if focusedPane == .before {
            _ = beforeStrokes.popLast()
        } else {
            _ = afterStrokes.popLast()
        }
    }

    private func clearDrawings() {
        if focusedPane == .before {
            beforeStrokes.removeAll()
            beforeCurrentStroke = nil
        } else {
            afterStrokes.removeAll()
            afterCurrentStroke = nil
        }
    }

    private func toggleCoachAnalysisRecording() {
        if isRecordingCoachAnalysis {
            stopCoachAnalysisRecording()
        } else {
            startCoachAnalysisRecording()
        }
    }

    private func startCoachAnalysisRecording() {
        guard student != nil else {
            coachAnalysisStatus = VideoSaveStatus(
                title: "Recording Unavailable",
                message: "Open this comparison from a student profile before recording coach analysis."
            )
            isShowingCoachAnalysisStatus = true
            return
        }

        isDrawingEnabled = true
        pauseBoth()

        Task {
            do {
                try await coachAnalysisRecorder.start()
                isRecordingCoachAnalysis = true
            } catch {
                coachAnalysisStatus = VideoSaveStatus(title: "Recording Failed", message: error.localizedDescription)
                isShowingCoachAnalysisStatus = true
            }
        }
    }

    private func stopCoachAnalysisRecording() {
        Task {
            do {
                let outputURL = try await coachAnalysisRecorder.stop()
                isRecordingCoachAnalysis = false
                let analysis = CoachAnalysisVideo(
                    title: "Coach Analysis",
                    recordedAt: .now,
                    fileURLString: VideoFileStore.persistedFileName(for: outputURL),
                    notes: coachAnalysisNotes(),
                    lessonDate: beforeVideo.lessonDate ?? afterVideo.lessonDate ?? beforeVideo.recordedAt
                )
                student?.coachAnalysisVideos.append(analysis)
                coachAnalysisStatus = VideoSaveStatus(
                    title: "Analysis Saved",
                    message: "The coach analysis video was saved under this student's profile."
                )
                isShowingCoachAnalysisStatus = true
            } catch {
                isRecordingCoachAnalysis = false
                coachAnalysisStatus = VideoSaveStatus(title: "Recording Failed", message: error.localizedDescription)
                isShowingCoachAnalysisStatus = true
            }
        }
    }

    private func coachAnalysisNotes() -> String {
        [
            "Comparison coach analysis",
            "Before: \(beforeVideo.title)",
            "After: \(afterVideo.title)",
            "Before frame: \(beforeFrame)",
            "After frame: \(afterFrame)",
            "Before annotations: \(beforeStrokes.count)",
            "After annotations: \(afterStrokes.count)",
            "Playback speed: \(String(format: "%.1fx", playbackRate))"
        ].joined(separator: "\n")
    }

    private func playBoth() {
        guard !isSeekingBefore, !isSeekingAfter else { return }
        beforePlayer.playImmediately(atRate: playbackRate)
        afterPlayer.playImmediately(atRate: playbackRate)
        isPlaying = true
    }

    private func pauseBoth() {
        beforePlayer.pause()
        afterPlayer.pause()
        isPlaying = false
    }

    private func requestFrameSeek(for pane: ComparisonPane, to frame: Int) {
        pauseBoth()
        let selectedFrame = min(max(frame, 0), totalFrames(for: pane))
        let targetSeconds = time(for: selectedFrame, pane: pane)
        setFrame(selectedFrame, for: pane)
        updateProgress(for: pane, seconds: targetSeconds)
        queueSeek(for: pane, to: targetSeconds)
    }

    private func queueSeek(for pane: ComparisonPane, to seconds: Double) {
        switch pane {
        case .before:
            chasedBeforeSeconds = seconds
            guard !isSeekingBefore else { return }
            isSeekingBefore = true
            beforeSeekTask = Task { @MainActor in
                while let targetSeconds = chasedBeforeSeconds, !Task.isCancelled {
                    chasedBeforeSeconds = nil
                    await seek(beforePlayer, to: targetSeconds)
                }
                isSeekingBefore = false
                beforeSeekTask = nil
                saveComparisonState()
            }
        case .after:
            chasedAfterSeconds = seconds
            guard !isSeekingAfter else { return }
            isSeekingAfter = true
            afterSeekTask = Task { @MainActor in
                while let targetSeconds = chasedAfterSeconds, !Task.isCancelled {
                    chasedAfterSeconds = nil
                    await seek(afterPlayer, to: targetSeconds)
                }
                isSeekingAfter = false
                afterSeekTask = nil
                saveComparisonState()
            }
        }
    }

    @MainActor
    private func loadPlaybackMetadata() async {
        let beforeMetadata = await playbackMetadata(for: beforeURL)
        let afterMetadata = await playbackMetadata(for: afterURL)

        beforeDuration = beforeMetadata.duration
        afterDuration = afterMetadata.duration
        beforeFPS = beforeMetadata.fps
        afterFPS = afterMetadata.fps
        beforeAspectRatio = beforeMetadata.aspectRatio
        afterAspectRatio = afterMetadata.aspectRatio
    }

    @MainActor
    private func playbackMetadata(for url: URL) async -> (duration: Double, fps: Double, aspectRatio: CGFloat) {
        let asset = AVURLAsset(url: url)
        let loadedDuration = (try? await asset.load(.duration).seconds) ?? 0
        let duration = loadedDuration.isFinite ? max(loadedDuration, 0) : 0
        let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        guard let track = tracks.first else {
            return (duration, 30, 9.0 / 16.0)
        }

        let aspectRatio = await videoAspectRatio(for: track)
        let nominalFrameRate = Double((try? await track.load(.nominalFrameRate)) ?? 0)
        if nominalFrameRate.isFinite, nominalFrameRate > 0 {
            return (duration, nominalFrameRate, aspectRatio)
        }

        let loadedFrameDuration = (try? await track.load(.minFrameDuration).seconds) ?? 0
        if loadedFrameDuration.isFinite, loadedFrameDuration > 0 {
            return (duration, 1.0 / loadedFrameDuration, aspectRatio)
        }

        return (duration, 30, aspectRatio)
    }

    @MainActor
    private func videoAspectRatio(for track: AVAssetTrack) async -> CGFloat {
        let naturalSize = (try? await track.load(.naturalSize)) ?? .zero
        let preferredTransform = (try? await track.load(.preferredTransform)) ?? .identity
        let transformedSize = naturalSize.applying(preferredTransform)
        let displaySize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
        guard displaySize.width > 0, displaySize.height > 0 else {
            return 9.0 / 16.0
        }
        return displaySize.width / displaySize.height
    }

    @MainActor
    private func seek(_ player: AVPlayer, to targetSeconds: Double) async {
        let targetTime = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        _ = await player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func totalFrames(for pane: ComparisonPane) -> Int {
        max(Int(duration(for: pane) * fps(for: pane)), 0)
    }

    private func frame(for seconds: Double, pane: ComparisonPane) -> Int {
        min(max(Int(seconds * fps(for: pane)), 0), totalFrames(for: pane))
    }

    private func time(for frame: Int, pane: ComparisonPane) -> Double {
        let duration = duration(for: pane)
        return min(Double(min(max(frame, 0), totalFrames(for: pane))) / fps(for: pane), duration)
    }

    private func duration(for pane: ComparisonPane) -> Double {
        pane == .before ? beforeDuration : afterDuration
    }

    private func fps(for pane: ComparisonPane) -> Double {
        pane == .before ? max(beforeFPS, 1.0) : max(afterFPS, 1.0)
    }

    private func setFrame(_ frame: Int, for pane: ComparisonPane) {
        if pane == .before {
            beforeFrame = frame
        } else {
            afterFrame = frame
        }
    }

    private func updateProgress(for pane: ComparisonPane, seconds: Double) {
        let progress = duration(for: pane) > 0 ? min(max(seconds / duration(for: pane), 0), 1) : 0
        if pane == .before {
            beforeProgress = progress
        } else {
            afterProgress = progress
        }
    }

    private func handleScrubbingChange(_ editing: Bool) {
        if editing {
            pauseBoth()
        } else {
            saveComparisonState()
        }
    }

    private func addTimeObservers() {
        let interval = CMTime(seconds: 1.0 / max(beforeFPS, afterFPS, 1.0), preferredTimescale: 600)
        beforeTimeObserver = beforePlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard !isBeforeScrubbing, !isSeekingBefore, beforeDuration > 0 else { return }
            beforeFrame = frame(for: time.seconds, pane: .before)
            beforeProgress = min(max(time.seconds / beforeDuration, 0), 1)
        }
        afterTimeObserver = afterPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard !isAfterScrubbing, !isSeekingAfter, afterDuration > 0 else { return }
            afterFrame = frame(for: time.seconds, pane: .after)
            afterProgress = min(max(time.seconds / afterDuration, 0), 1)
        }
    }

    private func removeTimeObservers() {
        if let beforeTimeObserver {
            beforePlayer.removeTimeObserver(beforeTimeObserver)
            self.beforeTimeObserver = nil
        }
        if let afterTimeObserver {
            afterPlayer.removeTimeObserver(afterTimeObserver)
            self.afterTimeObserver = nil
        }
    }

    private func saveComparisonState() {
        sessionStateManager.updateComparison(
            beforeVideo: beforeVideo,
            afterVideo: afterVideo,
            playbackSpeed: playbackRate,
            beforeProgress: beforeProgress,
            afterProgress: afterProgress
        )
    }
}

private struct AspectFitVideoView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        if uiView.player !== player {
            uiView.player = player
        }
    }

    class PlayerLayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }

        private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        var player: AVPlayer? {
            get { playerLayer.player }
            set {
                playerLayer.player = newValue
                playerLayer.videoGravity = .resizeAspect
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
            playerLayer.videoGravity = .resizeAspect
        }
    }
}

private struct ComparisonVideoPane: View {
    let title: LocalizedStringKey
    let video: LessonVideo
    let player: AVPlayer
    let duration: Double
    @Binding var progress: Double
    @Binding var strokes: [SwingAnalysisStroke]
    @Binding var currentStroke: SwingAnalysisStroke?
    let isDrawingEnabled: Bool
    let drawingTool: SwingDrawingTool
    let drawingColor: SwingDrawingColor
    let isSelectedForDrawing: Bool
    let videoAspectRatio: CGFloat
    let maxVideoHeight: CGFloat
    let compact: Bool
    let frameLabel: String
    let currentFrame: Int
    let totalFrames: Int
    @Binding var zoomScale: CGFloat
    @Binding var zoomOffset: CGSize
    @Binding var lastZoomScale: CGFloat
    @Binding var lastZoomOffset: CGSize
    let onSelect: () -> Void
    let onFrameRequested: (Int) -> Void
    let onScrubbingChanged: (Bool) -> Void
    @State private var hasConfiguredInitialZoom = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button(action: onSelect) {
                HStack {
                    Text(title)
                        .font(.caption.weight(.semibold))
                    if isDrawingEnabled && isSelectedForDrawing {
                        Label("Drawing", systemImage: "pencil")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            zoomableVideoSurface

            FrameScrubberControls(
                label: frameLabel,
                currentFrame: currentFrame,
                totalFrames: totalFrames,
                onFrameRequested: onFrameRequested,
                onScrubbingChanged: onScrubbingChanged
            )

            HStack {
                Text(formattedTime(progress * duration))
                Spacer()
                Text(formattedTime(duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)

            if !compact {
                Text(video.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelectedForDrawing && isDrawingEnabled ? .purple : .clear, lineWidth: 2)
        }
    }

    private var zoomableVideoSurface: some View {
        GeometryReader { proxy in
            ZStack {
                ZStack {
                    AspectFitVideoView(player: player)
                        .allowsHitTesting(false)
                    SwingDrawingOverlay(
                        strokes: $strokes,
                        currentStroke: $currentStroke,
                        selectedTool: .constant(drawingTool),
                        selectedColor: .constant(drawingColor),
                        isDrawingEnabled: isDrawingEnabled && isSelectedForDrawing,
                        onUndo: { _ = strokes.popLast() },
                        onZoomBegan: { beginZoom() },
                        onZoomChanged: { relativeScale in
                            updateZoom(relativeScale: relativeScale, in: proxy.size)
                        },
                        onZoomEnded: { commitTransform(in: proxy.size) },
                        onZoomPanBegan: { beginPan() },
                        onZoomPanChanged: { translation in
                            updatePan(translation: translation, in: proxy.size)
                        }
                    )
                }
                .scaleEffect(zoomScale)
                .offset(zoomOffset)
            }
            .onAppear {
                configureInitialZoomIfNeeded(in: proxy.size)
            }
            .onChange(of: proxy.size) { _, newSize in
                clampToValidZoomRange(in: newSize)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .contentShape(Rectangle())
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .gesture(videoTransformGesture(in: proxy.size), isEnabled: !isDrawingEnabled)
            .onTapGesture(count: 2) {
                guard !isDrawingEnabled else { return }
                resetZoom()
            }
            .onTapGesture(perform: onSelect)
        }
        .frame(maxWidth: .infinity)
        .frame(height: maxVideoHeight)
    }

    private func videoTransformGesture(in size: CGSize) -> some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    updateZoom(relativeScale: value, in: size)
                }
                .onEnded { _ in
                    commitTransform(in: size)
                },
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    updatePan(translation: value.translation, in: size)
                }
                .onEnded { _ in
                    commitTransform(in: size)
                }
        )
    }

    private func beginZoom() {
        lastZoomScale = zoomScale
    }

    private func updateZoom(relativeScale: CGFloat, in size: CGSize) {
        let range = zoomRange(in: size)
        let nextScale = min(max(lastZoomScale * relativeScale, range.minimum), range.maximum)
        zoomScale = nextScale
        zoomOffset = clampedOffset(zoomOffset, scale: nextScale, in: size)
        if nextScale == range.minimum {
            zoomOffset = .zero
            lastZoomOffset = .zero
        }
    }

    private func beginPan() {
        lastZoomOffset = zoomOffset
    }

    private func updatePan(translation: CGSize, in size: CGSize) {
        let range = zoomRange(in: size)
        guard zoomScale > range.minimum else {
            zoomOffset = .zero
            lastZoomOffset = .zero
            return
        }

        let proposed = CGSize(
            width: lastZoomOffset.width + translation.width,
            height: lastZoomOffset.height + translation.height
        )
        zoomOffset = clampedOffset(proposed, scale: zoomScale, in: size)
    }

    private func commitTransform(in size: CGSize) {
        let range = zoomRange(in: size)
        zoomScale = min(max(zoomScale, range.minimum), range.maximum)
        zoomOffset = zoomScale <= range.minimum ? .zero : clampedOffset(zoomOffset, scale: zoomScale, in: size)
        lastZoomScale = zoomScale
        lastZoomOffset = zoomOffset
    }

    private func resetZoom() {
        zoomScale = 1
        zoomOffset = .zero
        lastZoomScale = 1
        lastZoomOffset = .zero
    }

    private func clampedOffset(_ offset: CGSize, scale: CGFloat, in size: CGSize) -> CGSize {
        let range = zoomRange(in: size)
        guard scale > range.minimum else { return .zero }
        let extraScale = scale - range.minimum
        let maxX = max((size.width * extraScale) / 2, 0)
        let maxY = max((size.height * extraScale) / 2, 0)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    private func configureInitialZoomIfNeeded(in size: CGSize) {
        guard !hasConfiguredInitialZoom else { return }
        hasConfiguredInitialZoom = true
        let fillScale = zoomRange(in: size).fill
        zoomScale = fillScale
        lastZoomScale = fillScale
        zoomOffset = .zero
        lastZoomOffset = .zero
    }

    private func clampToValidZoomRange(in size: CGSize) {
        guard hasConfiguredInitialZoom else { return }
        commitTransform(in: size)
    }

    private func zoomRange(in size: CGSize) -> (minimum: CGFloat, fill: CGFloat, maximum: CGFloat) {
        let fillScale = fillScaleMultiplier(in: size)
        return (minimum: 1, fill: fillScale, maximum: max(fillScale * 4, 5))
    }

    private func fillScaleMultiplier(in size: CGSize) -> CGFloat {
        let aspectRatio = sanitizedVideoAspectRatio
        guard size.width > 0, size.height > 0 else { return 1 }

        let boxAspectRatio = size.width / size.height
        if aspectRatio > boxAspectRatio {
            let fitHeight = size.width / aspectRatio
            return max(size.height / max(fitHeight, 1), 1)
        } else {
            let fitWidth = size.height * aspectRatio
            return max(size.width / max(fitWidth, 1), 1)
        }
    }

    private var sanitizedVideoAspectRatio: CGFloat {
        guard videoAspectRatio.isFinite, videoAspectRatio > 0 else {
            return 9.0 / 16.0
        }
        return videoAspectRatio
    }

    private func formattedTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let totalSeconds = max(Int(seconds.rounded(.down)), 0)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private struct FrameScrubberControls: View {
    let label: String
    let currentFrame: Int
    let totalFrames: Int
    let onFrameRequested: (Int) -> Void
    let onScrubbingChanged: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(label) \(currentFrame) / \(totalFrames)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Button {
                    onFrameRequested(currentFrame - 1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(width: 36, height: 36)
                .accessibilityLabel("Previous frame")
                .disabled(currentFrame <= 0 || totalFrames == 0)

                Slider(
                    value: Binding(
                        get: { Double(currentFrame) },
                        set: { onFrameRequested(Int($0.rounded())) }
                    ),
                    in: 0...Double(max(totalFrames, 1)),
                    step: 1,
                    onEditingChanged: onScrubbingChanged
                )
                .tint(.purple)
                .frame(maxWidth: .infinity)
                .disabled(totalFrames == 0)

                Button {
                    onFrameRequested(currentFrame + 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(width: 36, height: 36)
                .accessibilityLabel("Next frame")
                .disabled(currentFrame >= totalFrames || totalFrames == 0)
            }
        }
    }
}

struct ProgressNote: View {
    let label: String
    let text: String?

    var body: some View {
        if let text, !text.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Lesson Sessions

struct LessonTimelineDay: Identifiable {
    let date: Date
    var appointments: [LessonAppointment] = []
    var notes: [LessonSessionNote] = []
    var swingVideos: [LessonVideo] = []
    var analysisVideos: [CoachAnalysisVideo] = []

    var id: Date { date }

    var assignmentCount: Int {
        notes.reduce(0) { count, note in
            let hasHomework = !note.homework.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return count + (hasHomework ? 1 : 0) + note.assignedDrills.count
        }
    }
}

private var _gcMigratedStudents = Set<PersistentIdentifier>()

private enum LessonVideoDisplayStore {
    static func uniqueVideos(in rawVideos: [LessonVideo]) -> [LessonVideo] {
        // Phase 1: deduplicate by normalized file path
        var filePathKeys = Set<String>()
        var fallbackKeys = Set<String>()
        var phase1: [LessonVideo] = []

        for video in rawVideos {
            if let key = filePathKey(for: video) {
                guard filePathKeys.insert(key).inserted else { continue }
            } else {
                let key = fallbackKey(for: video)
                guard fallbackKeys.insert(key).inserted else { continue }
            }
            phase1.append(video)
        }

        // Phase 2: deduplicate by content (file size) to catch duplicate copies of the same video file
        var contentKeys = Set<String>()
        var result: [LessonVideo] = []

        for video in phase1 {
            if let cKey = contentKey(for: video) {
                guard contentKeys.insert(cKey).inserted else { continue }
            }
            result.append(video)
        }

        return result
    }

    static func removeDuplicatesIfNeeded(in student: Student, context: ModelContext) {
        guard _gcMigratedStudents.insert(student.persistentModelID).inserted else { return }
        removeDuplicates(in: student, context: context)
    }

    static func removeDuplicates(in student: Student, context: ModelContext) {
        var filePathKeys = Set<String>()
        var contentKeys = Set<String>()
        var toDelete: [LessonVideo] = []

        for video in student.videos {
            var isFirstSeen = true

            if let key = filePathKey(for: video) {
                isFirstSeen = filePathKeys.insert(key).inserted
            }

            if isFirstSeen, let cKey = contentKey(for: video) {
                isFirstSeen = contentKeys.insert(cKey).inserted
            }

            if !isFirstSeen {
                toDelete.append(video)
                print("DEBUG migration: duplicate marked for deletion:", video.title, video.fileURLString ?? "nil")
            }
        }

        for video in toDelete {
            print("DEBUG migration: deleting duplicate:", video.title, video.fileURLString ?? "nil")
            VideoFileStore.deleteStoredVideoFile(for: video)
            student.videos.removeAll { $0.persistentModelID == video.persistentModelID }
            context.delete(video)
        }

        if !toDelete.isEmpty {
            print("DEBUG migration: removed \(toDelete.count) duplicate(s) for \(student.name)")
        }
    }

    static func containsVideo(in videos: [LessonVideo], matchingFileURL url: URL) -> Bool {
        let key = filePathKey(for: url)
        return videos.contains { video in
            filePathKey(for: video) == key
        }
    }

    static func containsVideo(in videos: [LessonVideo], matchingFileName fileName: String) -> Bool {
        let trimmedFileName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFileName.isEmpty else { return false }
        return videos.contains { video in
            guard let existingKey = filePathKey(for: video) else { return false }
            return existingKey == trimmedFileName || existingKey.hasSuffix("/\(trimmedFileName)")
        }
    }

    static func containsVideo(in videos: [LessonVideo], matchingContentOf url: URL) -> Bool {
        guard let newAttrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let newSize = newAttrs[.size] as? Int64, newSize > 0 else { return false }
        return videos.contains { video in
            guard let existingURL = video.fileURL,
                  let existingAttrs = try? FileManager.default.attributesOfItem(atPath: existingURL.path),
                  let existingSize = existingAttrs[.size] as? Int64, existingSize > 0 else { return false }
            return existingSize == newSize
        }
    }

    static func logVideos(rawVideos: [LessonVideo], uniqueVideos: [LessonVideo], context: String) async {
        print("RAW VIDEO COUNT:", rawVideos.count)
        print("UNIQUE VIDEO COUNT:", uniqueVideos.count)
        for video in rawVideos {
            let path = filePathKey(for: video) ?? "nil"
            let duration = await durationDescription(for: video.fileURL)
            let fileSize = fileSizeDescription(for: video.fileURL)
            print(
                "id:", String(describing: video.persistentModelID),
                "title:", video.title,
                "date:", video.lessonDate ?? video.recordedAt,
                "duration:", duration,
                "path:", path,
                "fileSize:", fileSize
            )
        }
    }

    private static func filePathKey(for video: LessonVideo) -> String? {
        if let url = video.fileURL {
            return filePathKey(for: url)
        }

        guard let rawValue = video.fileURLString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return nil
        }

        if let url = URL(string: rawValue), url.isFileURL {
            return filePathKey(for: url)
        }

        return rawValue
    }

    private static func filePathKey(for url: URL) -> String {
        url.resolvingSymlinksInPath().path
    }

    private static func contentKey(for video: LessonVideo) -> String? {
        guard let url = video.fileURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attrs[.size] as? Int64, fileSize > 0 else {
            return nil
        }
        return "size:\(fileSize)"
    }

    private static func fallbackKey(for video: LessonVideo) -> String {
        let date = video.lessonDate ?? video.recordedAt
        return "\(video.title)|\(date.timeIntervalSinceReferenceDate)"
    }

    private static func durationDescription(for url: URL?) async -> String {
        guard let url else { return "unknown" }
        let asset = AVURLAsset(url: url)
        do {
            let seconds = try await asset.load(.duration).seconds
            return seconds.isFinite ? "\(seconds)" : "unknown"
        } catch {
            return "unknown"
        }
    }

    private static func fileSizeDescription(for url: URL?) -> String {
        guard let url,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else {
            return "unknown"
        }
        return "\(size) bytes"
    }
}

private enum LessonTimelineBuilder {
    static func days(for student: Student) -> [LessonTimelineDay] {
        var days: [Date: LessonTimelineDay] = [:]
        let calendar = Calendar.current

        for lesson in student.lessons {
            let date = calendar.startOfDay(for: lesson.scheduledAt)
            days[date, default: LessonTimelineDay(date: date)].appointments.append(lesson)
        }
        for note in student.sessionNotes {
            let date = calendar.startOfDay(for: note.sessionDate)
            days[date, default: LessonTimelineDay(date: date)].notes.append(note)
        }
        for video in LessonVideoDisplayStore.uniqueVideos(in: student.videos) {
            let date = calendar.startOfDay(for: video.lessonDate ?? video.recordedAt)
            days[date, default: LessonTimelineDay(date: date)].swingVideos.append(video)
        }
        for analysis in student.coachAnalysisVideos {
            let date = calendar.startOfDay(for: analysis.lessonDate ?? analysis.recordedAt)
            days[date, default: LessonTimelineDay(date: date)].analysisVideos.append(analysis)
        }

        return days.values.sorted { $0.date > $1.date }
    }

    static func day(for student: Student, on date: Date) -> LessonTimelineDay {
        days(for: student).first { Calendar.current.isDate($0.date, inSameDayAs: date) }
            ?? LessonTimelineDay(date: Calendar.current.startOfDay(for: date))
    }
}

struct LessonTimelineSection: View {
    @Bindable var student: Student
    let sessionStateManager: SessionStateManager
    let onCaptureVideo: (Date) -> Void
    let onAddVideo: (Date) -> Void
    let onPlayVideo: (LessonVideo, Student) -> Void
    let onPlayCoachAnalysis: (CoachAnalysisVideo) -> Void
    let onShareNote: (LessonSessionNote) -> Void
    let onAddSessionNote: (Date) -> Void
    let onEditNote: (LessonSessionNote) -> Void
    let onEditVideo: (LessonVideo) -> Void
    let onEditAnalysis: (CoachAnalysisVideo) -> Void

    private var days: [LessonTimelineDay] {
        LessonTimelineBuilder.days(for: student)
    }

    var body: some View {
        Section("Lesson Timeline") {
            timelineActionButtons

            if days.isEmpty {
                Text("No lesson sessions yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(days) { day in
                    NavigationLink {
                        LessonDayDetailView(
                            student: student,
                            date: day.date,
                            sessionStateManager: sessionStateManager,
                            restoreComparisonOnAppear: false,
                            onCaptureVideo: onCaptureVideo,
                            onAddVideo: onAddVideo,
                            onPlayVideo: onPlayVideo,
                            onPlayCoachAnalysis: onPlayCoachAnalysis,
                            onShareNote: onShareNote,
                            onAddSessionNote: onAddSessionNote,
                            onEditNote: onEditNote,
                            onEditVideo: onEditVideo,
                            onEditAnalysis: onEditAnalysis
                        )
                    } label: {
                        LessonTimelineCard(day: day)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listRowBackground(StudentDetailSectionTint.lessons)
    }

    @ViewBuilder
    private var timelineActionButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                timelineButton(
                    title: "Add Lesson Notes",
                    systemImage: "note.text.badge.plus",
                    action: { onAddSessionNote(.now) }
                )
                timelineButton(
                    title: "Add Video",
                    systemImage: "video.badge.plus",
                    action: { onAddVideo(.now) }
                )
            }

            VStack(spacing: 8) {
                timelineButton(
                    title: "Add Lesson Notes",
                    systemImage: "note.text.badge.plus",
                    action: { onAddSessionNote(.now) }
                )
                timelineButton(
                    title: "Add Video",
                    systemImage: "video.badge.plus",
                    action: { onAddVideo(.now) }
                )
            }
        }
    }

    private func timelineButton(title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
        }
        .buttonStyle(.bordered)
    }
}

struct LessonTimelineCard: View {
    let day: LessonTimelineDay

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(day.date, format: .dateTime.weekday(.wide).month(.wide).day().year())
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            if !day.appointments.isEmpty {
                Text(day.appointments.sorted { $0.scheduledAt < $1.scheduledAt }
                    .map { $0.scheduledAt.formatted(date: .omitted, time: .shortened) }
                    .joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                LessonTimelineMetricChip(label: "Notes", value: day.notes.count, systemImage: "note.text")
                LessonTimelineMetricChip(label: "Videos", value: day.swingVideos.count, systemImage: "video")
                LessonTimelineMetricChip(label: "Analysis", value: day.analysisVideos.count, systemImage: "figure.golf")
                LessonTimelineMetricChip(label: "Practice", value: day.assignmentCount, systemImage: "checklist")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct LessonTimelineMetricChip: View {
    let label: LocalizedStringKey
    let value: Int
    let systemImage: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.purple)
                .frame(width: 16)

            Text(label)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 4)

            Text("\(value)")
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(.primary)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(.quaternary, lineWidth: 0.5)
            }
    }
}

struct LessonDayDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var student: Student
    let date: Date
    let sessionStateManager: SessionStateManager
    let restoreComparisonOnAppear: Bool
    let onCaptureVideo: (Date) -> Void
    let onAddVideo: (Date) -> Void
    let onPlayVideo: (LessonVideo, Student) -> Void
    let onPlayCoachAnalysis: (CoachAnalysisVideo) -> Void
    let onShareNote: (LessonSessionNote) -> Void
    let onAddSessionNote: (Date) -> Void
    let onEditNote: (LessonSessionNote) -> Void
    let onEditVideo: (LessonVideo) -> Void
    let onEditAnalysis: (CoachAnalysisVideo) -> Void

    @State private var notePendingDeletion: LessonSessionNote?
    @State private var videoPendingDeletion: LessonVideo?
    @State private var analysisPendingDeletion: CoachAnalysisVideo?
    @State private var lessonForCalendar: LessonAppointment?
    @State private var isComparingVideos = false

    private var day: LessonTimelineDay {
        LessonTimelineBuilder.day(for: student, on: date)
    }

    private var uniqueStudentVideos: [LessonVideo] {
        LessonVideoDisplayStore.uniqueVideos(in: student.videos)
    }

    private var savedComparisonVideosAvailable: Bool {
        let state = sessionStateManager.state
        return student.videos.contains {
            $0.fileURL != nil && sessionStateManager.matches($0, storedIdentifier: state.beforeComparisonVideoID)
        } && student.videos.contains {
            $0.fileURL != nil && sessionStateManager.matches($0, storedIdentifier: state.afterComparisonVideoID)
        }
    }

    var body: some View {
        Form {
            scheduledLessonsSection
            lessonNotesSection
            lessonVideosSection
            coachAnalysisSection
        }
        .navigationTitle(date.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $lessonForCalendar) { lesson in
            CalendarEventEditor(student: student, lesson: lesson)
        }
        .fullScreenCover(isPresented: $isComparingVideos) {
            SwingComparisonSelectionView(
                student: student,
                lessonDate: date,
                sessionStateManager: sessionStateManager,
                restoreComparisonOnAppear: restoreComparisonOnAppear
            )
        }
        .task {
            sessionStateManager.selectLessonDate(date, preservingComparison: restoreComparisonOnAppear)
            if restoreComparisonOnAppear && sessionStateManager.state.hasComparison && savedComparisonVideosAvailable {
                isComparingVideos = true
            }
        }
        .alert("Delete Lesson Notes", isPresented: Binding(
            get: { notePendingDeletion != nil },
            set: { if !$0 { notePendingDeletion = nil } }
        ), presenting: notePendingDeletion) { note in
            Button("Delete", role: .destructive) {
                student.sessionNotes.removeAll { $0.persistentModelID == note.persistentModelID }
                modelContext.delete(note)
                notePendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { notePendingDeletion = nil }
        } message: { _ in
            Text("Are you sure you want to delete these lesson notes? This cannot be undone.")
        }
        .alert("Delete Video", isPresented: Binding(
            get: { videoPendingDeletion != nil },
            set: { if !$0 { videoPendingDeletion = nil } }
        ), presenting: videoPendingDeletion) { video in
            Button("Delete", role: .destructive) {
                VideoFileStore.deleteStoredVideoFile(for: video)
                student.videos.removeAll { $0.persistentModelID == video.persistentModelID }
                modelContext.delete(video)
                videoPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { videoPendingDeletion = nil }
        } message: { _ in
            Text("Are you sure you want to delete this video? This cannot be undone.")
        }
        .alert("Delete Coach Analysis Video", isPresented: Binding(
            get: { analysisPendingDeletion != nil },
            set: { if !$0 { analysisPendingDeletion = nil } }
        ), presenting: analysisPendingDeletion) { analysis in
            Button("Delete", role: .destructive) {
                if let url = analysis.fileURL { try? FileManager.default.removeItem(at: url) }
                student.coachAnalysisVideos.removeAll { $0.persistentModelID == analysis.persistentModelID }
                modelContext.delete(analysis)
                analysisPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { analysisPendingDeletion = nil }
        } message: { _ in
            Text("Are you sure you want to delete this coach analysis video? This cannot be undone.")
        }
    }

    private var scheduledLessonsSection: some View {
        Section("Scheduled Lesson") {
            if day.appointments.isEmpty {
                Text("No lesson scheduled for this date")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(day.appointments.sorted { $0.scheduledAt < $1.scheduledAt }) { lesson in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(lesson.title)
                                .font(.headline)
                            Spacer()
                            Toggle("Done", isOn: Binding(
                                get: { lesson.isCompleted },
                                set: { lesson.isCompleted = $0 }
                            ))
                            .labelsHidden()
                        }
                        Text(lesson.scheduledAt, format: .dateTime.hour().minute())
                            .foregroundStyle(.secondary)
                        if !lesson.location.isEmpty {
                            Label(lesson.location, systemImage: "mappin.and.ellipse")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !lesson.notes.isEmpty {
                            Text(lesson.notes)
                                .font(.subheadline)
                        }
                        HStack {
                            Label(lesson.reminderLeadTime.rawValue, systemImage: "bell")
                            Spacer()
                            Button {
                                lessonForCalendar = lesson
                            } label: {
                                Label("Calendar", systemImage: "calendar.badge.plus")
                            }
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { offsets in
                    let lessons = day.appointments.sorted { $0.scheduledAt < $1.scheduledAt }
                    for index in offsets {
                        let lesson = lessons[index]
                        student.lessons.removeAll { $0.persistentModelID == lesson.persistentModelID }
                        modelContext.delete(lesson)
                    }
                }
            }
        }
        .listRowBackground(StudentDetailSectionTint.lessons)
    }

    private var lessonNotesSection: some View {
        Section("Lesson Session Notes") {
            Button {
                onAddSessionNote(date)
            } label: {
                Label("Add Lesson Notes", systemImage: "note.text.badge.plus")
            }

            if day.notes.isEmpty {
                Text("No notes added yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(day.notes.sorted { $0.sessionDate > $1.sessionDate }) { note in
                    SessionNoteCard(note: note) {
                        onEditNote(note)
                    } onShare: {
                        onShareNote(note)
                    }
                }
                .onDelete { offsets in
                    let notes = day.notes.sorted { $0.sessionDate > $1.sessionDate }
                    if let index = offsets.first { notePendingDeletion = notes[index] }
                }
            }
        }
        .listRowBackground(StudentDetailSectionTint.notes)
    }

    private var lessonVideosSection: some View {
        Section("Lesson Videos") {
            Button {
                onCaptureVideo(date)
            } label: {
                Label("Capture Swing Video", systemImage: "camera")
            }
            Button {
                onAddVideo(date)
            } label: {
                Label("Import / Add Video", systemImage: "video.badge.plus")
            }
            if uniqueStudentVideos.filter({ $0.fileURL != nil }).count >= 2 {
                Button {
                    isComparingVideos = true
                } label: {
                    Label("Compare Videos", systemImage: "square.split.2x1")
                }
            }

            if day.swingVideos.isEmpty {
                Text("No swing videos saved")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(day.swingVideos.sorted { $0.recordedAt > $1.recordedAt }) { video in
                    LessonVideoRow(
                        video: video,
                        defaultFocusNotes: "",
                        defaultProblemNotes: "",
                        onPlay: { onPlayVideo(video, student) },
                        onEdit: { onEditVideo(video) }
                    )
                }
                .onDelete { offsets in
                    let videos = day.swingVideos.sorted { $0.recordedAt > $1.recordedAt }
                    if let index = offsets.first { videoPendingDeletion = videos[index] }
                }
            }
        }
        .listRowBackground(StudentDetailSectionTint.videos)
    }

    private var coachAnalysisSection: some View {
        Section("Coach Analysis Videos") {
            if day.analysisVideos.isEmpty {
                Text("No coach analysis videos saved")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(day.analysisVideos.sorted { $0.recordedAt > $1.recordedAt }) { analysis in
                    SessionAnalysisRow(analysis: analysis) {
                        onPlayCoachAnalysis(analysis)
                    } onEdit: {
                        onEditAnalysis(analysis)
                    }
                }
                .onDelete { offsets in
                    let analyses = day.analysisVideos.sorted { $0.recordedAt > $1.recordedAt }
                    if let index = offsets.first { analysisPendingDeletion = analyses[index] }
                }
            }
        }
        .listRowBackground(StudentDetailSectionTint.coachAnalysis)
    }
}

struct LessonSessionGroup: Identifiable {
    let date: Date
    var note: LessonSessionNote?
    var swingVideos: [LessonVideo]
    var analysisVideos: [CoachAnalysisVideo]
    var id: Date { date }

    init(date: Date, note: LessonSessionNote? = nil, swingVideos: [LessonVideo] = [], analysisVideos: [CoachAnalysisVideo] = []) {
        self.date = date
        self.note = note
        self.swingVideos = swingVideos
        self.analysisVideos = analysisVideos
    }
}

struct LessonSessionsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var student: Student
    let onCaptureVideo: () -> Void
    let onAddVideo: () -> Void
    let onPlayVideo: (LessonVideo, Student) -> Void
    let onPlayCoachAnalysis: (CoachAnalysisVideo) -> Void
    let onShareNote: (LessonSessionNote) -> Void
    let onAddSessionNote: (Date) -> Void
    let onEditNote: (LessonSessionNote) -> Void
    let onEditVideo: (LessonVideo) -> Void
    let onEditAnalysis: (CoachAnalysisVideo) -> Void

    @State private var notePendingDeletion: LessonSessionNote?
    @State private var videoPendingDeletion: LessonVideo?
    @State private var analysisPendingDeletion: CoachAnalysisVideo?

    var sessionGroups: [LessonSessionGroup] {
        var groups: [Date: LessonSessionGroup] = [:]
        let cal = Calendar.current
        for video in LessonVideoDisplayStore.uniqueVideos(in: student.videos) {
            let day = cal.startOfDay(for: video.lessonDate ?? video.recordedAt)
            if groups[day] == nil { groups[day] = LessonSessionGroup(date: day) }
            groups[day]!.swingVideos.append(video)
        }
        for analysis in student.coachAnalysisVideos {
            let day = cal.startOfDay(for: analysis.lessonDate ?? analysis.recordedAt)
            if groups[day] == nil { groups[day] = LessonSessionGroup(date: day) }
            groups[day]!.analysisVideos.append(analysis)
        }
        for note in student.sessionNotes {
            let day = cal.startOfDay(for: note.sessionDate)
            if groups[day] == nil { groups[day] = LessonSessionGroup(date: day) }
            groups[day]!.note = note
        }
        return groups.values.sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            Section("Lesson Sessions") {
                Button {
                    onAddSessionNote(.now)
                } label: {
                    Label("Add Lesson Notes", systemImage: "note.text.badge.plus")
                }
                Button(action: onCaptureVideo) {
                    Label("Capture Swing Video", systemImage: "camera")
                }
                Button(action: onAddVideo) {
                    Label("Import / Add Video", systemImage: "video.badge.plus")
                }
                if sessionGroups.isEmpty {
                    Text("No lesson sessions yet")
                        .foregroundStyle(.secondary)
                }
            }
            .listRowBackground(StudentDetailSectionTint.videos)

            ForEach(sessionGroups) { group in
                Section {
                    if let note = group.note {
                        ForEach([note]) { n in
                            SessionNoteCard(note: n) {
                                onEditNote(n)
                            } onShare: {
                                onShareNote(n)
                            }
                        }
                        .onDelete { _ in
                            notePendingDeletion = note
                        }
                    } else {
                        Button {
                            onAddSessionNote(group.date)
                        } label: {
                            Label("Add Lesson Notes", systemImage: "note.text.badge.plus")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }

                    ForEach(group.swingVideos.sorted { $0.recordedAt > $1.recordedAt }) { video in
                        LessonVideoRow(
                            video: video,
                            defaultFocusNotes: "",
                            defaultProblemNotes: "",
                            onPlay: { onPlayVideo(video, student) },
                            onEdit: { onEditVideo(video) }
                        )
                    }
                    .onDelete { offsets in
                        let sorted = group.swingVideos.sorted { $0.recordedAt > $1.recordedAt }
                        if let i = offsets.first {
                            videoPendingDeletion = sorted[i]
                        }
                    }

                    ForEach(group.analysisVideos.sorted { $0.recordedAt > $1.recordedAt }) { analysis in
                        SessionAnalysisRow(analysis: analysis) {
                            onPlayCoachAnalysis(analysis)
                        } onEdit: {
                            onEditAnalysis(analysis)
                        }
                    }
                    .onDelete { offsets in
                        let sorted = group.analysisVideos.sorted { $0.recordedAt > $1.recordedAt }
                        if let i = offsets.first {
                            analysisPendingDeletion = sorted[i]
                        }
                    }
                } header: {
                    Text(group.date, format: .dateTime.weekday(.wide).month(.wide).day().year())
                        .font(.subheadline.weight(.semibold))
                        .textCase(nil)
                        .foregroundStyle(.primary)
                }
                .listRowBackground(StudentDetailSectionTint.videos)
            }
        }
        .alert("Delete Lesson Notes", isPresented: Binding(
            get: { notePendingDeletion != nil },
            set: { if !$0 { notePendingDeletion = nil } }
        ), presenting: notePendingDeletion) { note in
            Button("Delete", role: .destructive) {
                student.sessionNotes.removeAll { $0.persistentModelID == note.persistentModelID }
                modelContext.delete(note)
                notePendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                notePendingDeletion = nil
            }
        } message: { _ in
            Text("Are you sure you want to delete these lesson notes? This cannot be undone.")
        }
        .alert("Delete Video", isPresented: Binding(
            get: { videoPendingDeletion != nil },
            set: { if !$0 { videoPendingDeletion = nil } }
        ), presenting: videoPendingDeletion) { video in
            Button("Delete", role: .destructive) {
                VideoFileStore.deleteStoredVideoFile(for: video)
                student.videos.removeAll { $0.persistentModelID == video.persistentModelID }
                modelContext.delete(video)
                videoPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                videoPendingDeletion = nil
            }
        } message: { _ in
            Text("Are you sure you want to delete this video? This cannot be undone.")
        }
        .alert("Delete Coach Analysis Video", isPresented: Binding(
            get: { analysisPendingDeletion != nil },
            set: { if !$0 { analysisPendingDeletion = nil } }
        ), presenting: analysisPendingDeletion) { analysis in
            Button("Delete", role: .destructive) {
                if let url = analysis.fileURL { try? FileManager.default.removeItem(at: url) }
                student.coachAnalysisVideos.removeAll { $0.persistentModelID == analysis.persistentModelID }
                modelContext.delete(analysis)
                analysisPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                analysisPendingDeletion = nil
            }
        } message: { _ in
            Text("Are you sure you want to delete this coach analysis video? This cannot be undone.")
        }
    }
}

struct SessionNoteCard: View {
    let note: LessonSessionNote
    let onEdit: () -> Void
    let onShare: () -> Void
    @State private var previewAttachment: LessonNoteImageAttachment?

    var hasContent: Bool {
        !note.lessonFocus.isEmpty ||
        !note.coachNotes.isEmpty ||
        !note.homework.isEmpty ||
        !note.drills.isEmpty ||
        !note.nextLessonGoal.isEmpty ||
        !note.privateCoachJournal.isEmpty ||
        !note.focus.isEmpty ||
        !note.problems.isEmpty ||
        !note.improvements.isEmpty ||
        !note.generalNotes.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !hasContent {
                Text("No notes added yet")
                    .foregroundStyle(.secondary)
                    .italic()
                    .font(.subheadline)
            } else {
                if !note.lessonFocus.isEmpty { SessionNoteField(label: "Lesson Focus", text: note.lessonFocus) }
                if !note.coachNotes.isEmpty { SessionNoteField(label: "Coach Notes", text: note.coachNotes) }
                if !note.homework.isEmpty { SessionNoteField(label: "Assigned Homework", text: note.homework) }
                if !note.drills.isEmpty { SessionNoteField(label: "Drills", text: note.drills) }
                if !note.assignedDrills.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Assigned Drills")
                            .textCase(.uppercase)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(note.assignedDrills.sorted { $0.title < $1.title }) { drill in
                            AssignedDrillDisplayCard(drill: drill)
                        }
                    }
                }
                if !note.nextLessonGoal.isEmpty { SessionNoteField(label: "Next Lesson Goal", text: note.nextLessonGoal) }
                if !note.privateCoachJournal.isEmpty {
                    SessionNoteField(label: "Private Coach Journal", text: note.privateCoachJournal)
                }
                if !note.focus.isEmpty { SessionNoteField(label: "Today's Focus", text: note.focus) }
                if !note.problems.isEmpty { SessionNoteField(label: "Problem Areas", text: note.problems) }
                if !note.improvements.isEmpty { SessionNoteField(label: "Areas to Improve", text: note.improvements) }
                if !note.generalNotes.isEmpty { SessionNoteField(label: "Additional Notes", text: note.generalNotes) }
            }

            if !note.imageAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(note.imageAttachments.sorted { $0.createdAt < $1.createdAt }) { attachment in
                            if let image = UIImage(data: attachment.imageData) {
                                Button {
                                    previewAttachment = attachment
                                } label: {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 70, height: 70)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Open Swing Screenshot")
                            }
                        }
                    }
                }
            }

            HStack(spacing: 16) {
                Button(action: onEdit) {
                    Label("Edit Notes", systemImage: "pencil")
                }
                .font(.caption)
                .buttonStyle(.borderless)

                Button(action: onShare) {
                    Label("Share Summary", systemImage: "square.and.arrow.up")
                }
                .font(.caption)
                .buttonStyle(.borderless)

                Spacer()
            }
        }
        .padding(.vertical, 4)
        .fullScreenCover(item: $previewAttachment) { attachment in
            LessonNoteAttachmentPreviewView(attachment: attachment)
        }
    }
}

struct AssignedDrillDisplayCard: View {
    let drill: Drill

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(drill.title)
                .font(.subheadline.weight(.semibold))
            if !drill.purpose.isEmpty {
                Text(drill.purpose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !drill.recommendedReps.isEmpty {
                Text("Reps: \(drill.recommendedReps)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct LessonNoteAttachmentPreviewView: View {
    let attachment: LessonNoteImageAttachment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Spacer()

                if let image = UIImage(data: attachment.imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                }

                if !attachment.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(attachment.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                }
            }
            .navigationTitle("Swing Screenshot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct SessionNoteField: View {
    let label: LocalizedStringKey
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .textCase(.uppercase)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum StudentLessonSummaryFormatter {
    static func summary(for note: LessonSessionNote, studentName: String) -> String {
        let date = note.sessionDate.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        let name = value(studentName)
        let legacyCoachNotes = [note.problems, note.generalNotes]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")

        let fields: [(String, String)] = [
            (String(localized: "Student"), name),
            (String(localized: "Lesson Date"), date),
            (String(localized: "Today's Focus"), value(note.lessonFocus, fallback: note.focus)),
            (String(localized: "Coach Notes"), value(note.coachNotes, fallback: legacyCoachNotes)),
            (String(localized: "Assigned Homework"), value(note.homework)),
            (String(localized: "Drills"), value(note.drills, fallback: note.improvements)),
            (String(localized: "Next Lesson Goal"), value(note.nextLessonGoal))
        ]

        var details = fields.map { "\($0.0.uppercased())\n\($0.1)" }.joined(separator: "\n\n")
        if !note.assignedDrills.isEmpty {
            let drillSummaries = note.assignedDrills.sorted { $0.title < $1.title }.map { drill in
                [
                    drill.title,
                    "\(String(localized: "Purpose")): \(value(drill.purpose))",
                    "\(String(localized: "Instructions")): \(value(drill.instructions))",
                    "\(String(localized: "Recommended Reps")): \(value(drill.recommendedReps))",
                    "\(String(localized: "Coach Tips")): \(value(drill.coachTips))"
                ].joined(separator: "\n")
            }
            details += "\n\n\(String(localized: "Assigned Drills").uppercased())\n\(drillSummaries.joined(separator: "\n\n"))"
        }
        return "\(String(localized: "Golf Lesson Summary"))\n\n\(details)"
    }

    private static func value(_ value: String, fallback: String = "") -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        let trimmedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedFallback.isEmpty ? String(localized: "Not provided") : trimmedFallback
    }
}

struct SessionAnalysisRow: View {
    let analysis: CoachAnalysisVideo
    let onPlay: () -> Void
    let onEdit: () -> Void

    var displayDate: Date { analysis.lessonDate ?? analysis.recordedAt }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(analysis.title)
                    .font(.subheadline.weight(.semibold))
                Text(displayDate, format: .dateTime.month().day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !analysis.notes.isEmpty {
                    Text(analysis.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if analysis.fileURL == nil {
                    Text("Analysis not generated yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 12) {
                Button(action: onEdit) {
                    Image(systemName: "pencil.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)

                Button(action: onPlay) {
                    Label(
                        analysis.fileURL == nil ? "Create" : "Play",
                        systemImage: analysis.fileURL == nil ? "record.circle" : "play.circle"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(analysis.fileURL == nil ? .orange : .blue)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlay)
    }
}

struct EditCoachAnalysisView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var analysis: CoachAnalysisVideo
    @State private var title: String
    @State private var lessonDate: Date
    @State private var notes: String

    init(analysis: CoachAnalysisVideo) {
        self.analysis = analysis
        _title = State(initialValue: analysis.title)
        _lessonDate = State(initialValue: analysis.lessonDate ?? analysis.recordedAt)
        _notes = State(initialValue: analysis.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Analysis Info") {
                    TextField("Title", text: $title)
                    DatePicker("Lesson Date", selection: $lessonDate, displayedComponents: .date)
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        analysis.title = title
                        analysis.lessonDate = lessonDate
                        analysis.notes = notes
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct LessonNoteAttachmentDraft: Identifiable {
    let id = UUID()
    let imageData: Data
    let createdAt: Date
    var caption: String

    init(imageData: Data, createdAt: Date = .now, caption: String = "") {
        self.imageData = imageData
        self.createdAt = createdAt
        self.caption = caption
    }

    init(attachment: LessonNoteImageAttachment) {
        imageData = attachment.imageData
        createdAt = attachment.createdAt
        caption = attachment.caption
    }
}

private enum LessonNoteAttachmentImageProcessor {
    static func compressedData(from image: UIImage) -> Data? {
        let maxDimension: CGFloat = 1280
        let largestDimension = max(image.size.width, image.size.height)
        let scale = min(maxDimension / largestDimension, 1.0)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resizedImage.jpegData(compressionQuality: 0.8)
    }
}

struct EditSessionNoteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Drill.title) private var availableDrills: [Drill]

    let student: Student?
    let existingNote: LessonSessionNote?

    @State private var sessionDate: Date
    @State private var focus: String
    @State private var problems: String
    @State private var improvements: String
    @State private var generalNotes: String
    @State private var lessonFocus: String
    @State private var coachNotes: String
    @State private var homework: String
    @State private var drills: String
    @State private var nextLessonGoal: String
    @State private var privateCoachJournal: String
    @State private var attachmentDrafts: [LessonNoteAttachmentDraft]
    @State private var selectedAttachmentPhoto: PhotosPickerItem?
    @State private var isTakingAttachmentPhoto = false
    @State private var selectedAssignedDrills: [Drill]
    @State private var isSelectingAssignedDrills = false

    init(student: Student, defaultDate: Date = .now) {
        self.student = student
        self.existingNote = nil
        _sessionDate = State(initialValue: Calendar.current.startOfDay(for: defaultDate))
        _focus = State(initialValue: "")
        _problems = State(initialValue: "")
        _improvements = State(initialValue: "")
        _generalNotes = State(initialValue: "")
        _lessonFocus = State(initialValue: "")
        _coachNotes = State(initialValue: "")
        _homework = State(initialValue: "")
        _drills = State(initialValue: "")
        _nextLessonGoal = State(initialValue: "")
        _privateCoachJournal = State(initialValue: "")
        _attachmentDrafts = State(initialValue: [])
        _selectedAssignedDrills = State(initialValue: [])
    }

    init(existingNote: LessonSessionNote) {
        self.student = nil
        self.existingNote = existingNote
        _sessionDate = State(initialValue: existingNote.sessionDate)
        _focus = State(initialValue: existingNote.focus)
        _problems = State(initialValue: existingNote.problems)
        _improvements = State(initialValue: existingNote.improvements)
        _generalNotes = State(initialValue: existingNote.generalNotes)
        _lessonFocus = State(initialValue: existingNote.lessonFocus)
        _coachNotes = State(initialValue: existingNote.coachNotes)
        _homework = State(initialValue: existingNote.homework)
        _drills = State(initialValue: existingNote.drills)
        _nextLessonGoal = State(initialValue: existingNote.nextLessonGoal)
        _privateCoachJournal = State(initialValue: existingNote.privateCoachJournal)
        _attachmentDrafts = State(initialValue: existingNote.imageAttachments.map {
            LessonNoteAttachmentDraft(imageData: $0.imageData, createdAt: $0.createdAt, caption: $0.caption)
        })
        _selectedAssignedDrills = State(initialValue: existingNote.assignedDrills)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Lesson Date", selection: $sessionDate, displayedComponents: .date)
                }

                Section("Lesson Focus") {
                    TextField("What was the primary focus of this lesson?", text: $lessonFocus, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Coach Notes") {
                    TextField("What should the student remember from this lesson?", text: $coachNotes, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Assigned Homework") {
                    TextField("What should the student practice before the next lesson?", text: $homework, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Drills") {
                    TextField("Which drills were assigned?", text: $drills, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Assigned Drills") {
                    if availableDrills.isEmpty {
                        Text("No drills yet. Create one in Drill Library.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        if selectedAssignedDrills.isEmpty {
                            Text("No drills assigned.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(selectedAssignedDrills.sorted { $0.title < $1.title }) { drill in
                                AssignedDrillDisplayCard(drill: drill)
                            }
                        }

                        Button {
                            isSelectingAssignedDrills = true
                        } label: {
                            Label("Select Drills", systemImage: "checklist")
                        }
                    }
                }

                Section("Next Lesson Goal") {
                    TextField("What is the goal for the next lesson?", text: $nextLessonGoal, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Private Coach Journal") {
                    TextField("Private observations for the coach only", text: $privateCoachJournal, axis: .vertical)
                        .lineLimit(3...8)
                    Text("This journal is visible only in the coach app and is never included in student sharing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Attachments") {
                    PhotosPicker(selection: $selectedAttachmentPhoto, matching: .images) {
                        Label("Add Screenshot / Image", systemImage: "photo.badge.plus")
                    }

                    Button {
                        isTakingAttachmentPhoto = true
                    } label: {
                        Label("Take Photo", systemImage: "camera")
                    }
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

                    ForEach($attachmentDrafts) { $attachment in
                        HStack(alignment: .top, spacing: 12) {
                            if let image = UIImage(data: attachment.imageData) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                TextField("Caption (optional)", text: $attachment.caption, axis: .vertical)
                                    .lineLimit(1...3)
                                Text(attachment.createdAt, format: .dateTime.month().day().year().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Button(role: .destructive) {
                                removeAttachment(attachment.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete Attachment")
                        }
                    }
                }

                Section("Today's Focus") {
                    TextField("What did you work on today?", text: $focus, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Problem Areas") {
                    TextField("What issues were observed?", text: $problems, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Areas to Improve") {
                    TextField("Drills or homework for the student", text: $improvements, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Additional Notes") {
                    TextField("Any other notes...", text: $generalNotes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(existingNote == nil ? "New Lesson Notes" : "Edit Lesson Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .sheet(isPresented: $isTakingAttachmentPhoto) {
                CameraImagePicker { image in
                    addAttachment(image)
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $isSelectingAssignedDrills) {
                DrillSelectionView(
                    drills: availableDrills,
                    selectedDrills: $selectedAssignedDrills
                )
            }
            .onChange(of: selectedAttachmentPhoto) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        addAttachment(image)
                    }
                    selectedAttachmentPhoto = nil
                }
            }
        }
    }

    private func save() {
        if let note = existingNote {
            note.sessionDate = sessionDate
            note.focus = focus
            note.problems = problems
            note.improvements = improvements
            note.generalNotes = generalNotes
            note.lessonFocus = lessonFocus
            note.coachNotes = coachNotes
            note.homework = homework
            note.drills = drills
            note.nextLessonGoal = nextLessonGoal
            note.privateCoachJournal = privateCoachJournal
            note.assignedDrills = selectedAssignedDrills
            let replacedAttachments = note.imageAttachments
            note.imageAttachments = attachmentDrafts.map {
                LessonNoteImageAttachment(imageData: $0.imageData, createdAt: $0.createdAt, caption: $0.caption)
            }
            for attachment in replacedAttachments {
                modelContext.delete(attachment)
            }
        } else if let student {
            let note = LessonSessionNote(
                sessionDate: sessionDate,
                focus: focus,
                problems: problems,
                improvements: improvements,
                generalNotes: generalNotes,
                lessonFocus: lessonFocus,
                coachNotes: coachNotes,
                homework: homework,
                drills: drills,
                nextLessonGoal: nextLessonGoal,
                privateCoachJournal: privateCoachJournal,
                imageAttachments: attachmentDrafts.map {
                    LessonNoteImageAttachment(imageData: $0.imageData, createdAt: $0.createdAt, caption: $0.caption)
                },
                assignedDrills: selectedAssignedDrills
            )
            student.sessionNotes.append(note)
        }
        dismiss()
    }

    private func addAttachment(_ image: UIImage) {
        guard let imageData = LessonNoteAttachmentImageProcessor.compressedData(from: image) else { return }
        attachmentDrafts.append(LessonNoteAttachmentDraft(imageData: imageData))
    }

    private func removeAttachment(_ id: UUID) {
        attachmentDrafts.removeAll { $0.id == id }
    }
}

struct DrillSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    let drills: [Drill]
    @Binding var selectedDrills: [Drill]
    @State private var searchText = ""

    private var filteredDrills: [Drill] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return drills }
        return drills.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.category.localizedCaseInsensitiveContains(query) ||
            $0.purpose.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if drills.isEmpty {
                    ContentUnavailableView(
                        "No Drills",
                        systemImage: "list.bullet.clipboard",
                        description: Text("No drills yet. Create one in Drill Library.")
                    )
                } else if filteredDrills.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ForEach(filteredDrills.sorted { $0.title < $1.title }) { drill in
                        Button {
                            toggleAssignedDrill(drill)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(drill.title)
                                        .foregroundStyle(.primary)
                                    if !drill.category.isEmpty {
                                        Text(drill.category)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if isDrillAssigned(drill) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Select Drills")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search Drills")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func isDrillAssigned(_ drill: Drill) -> Bool {
        selectedDrills.contains { $0.persistentModelID == drill.persistentModelID }
    }

    private func toggleAssignedDrill(_ drill: Drill) {
        if isDrillAssigned(drill) {
            selectedDrills.removeAll { $0.persistentModelID == drill.persistentModelID }
        } else {
            selectedDrills.append(drill)
        }
    }
}

struct SessionNoteShareView: View {
    private enum MediaShareAlert: Identifiable {
        case missingVideo
        case largeVideo([URL])

        var id: String {
            switch self {
            case .missingVideo:
                return "missingVideo"
            case .largeVideo:
                return "largeVideo"
            }
        }
    }

    let note: LessonSessionNote
    let studentName: String
    let studentEmail: String
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingEmailComposer = false
    @State private var emailStatusMessage: String?
    @State private var isShowingEmailStatus = false
    @State private var mediaShareAlert: MediaShareAlert?

    var formattedText: String {
        StudentLessonSummaryFormatter.summary(for: note, studentName: studentName)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    Text(formattedText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }

                Divider()

                VStack(spacing: 10) {
                    Button {
                        emailLessonSummary()
                    } label: {
                        Label("Email Lesson Summary to Student", systemImage: "envelope")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        presentShareSheet(includeMedia: false)
                    } label: {
                        Label("Share Summary", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        shareSummaryWithMedia()
                    } label: {
                        Label("Share Summary + Media", systemImage: "photo.on.rectangle.angled")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .navigationTitle("Lesson Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isShowingEmailComposer) {
                LessonEmailComposerView(
                    recipients: [studentEmail.trimmingCharacters(in: .whitespacesAndNewlines)],
                    subject: String(localized: "Golf Lesson Summary"),
                    body: formattedText,
                    imageAttachments: note.imageAttachments
                        .sorted { $0.createdAt < $1.createdAt }
                        .map(\.imageData),
                    onFinish: { message in
                        if let message {
                            emailStatusMessage = message
                            isShowingEmailStatus = true
                        }
                    }
                )
            }
            .alert("Lesson Summary Email", isPresented: $isShowingEmailStatus, presenting: emailStatusMessage) { _ in
                Button("OK", role: .cancel) { }
            } message: { message in
                Text(message)
            }
            .alert(item: $mediaShareAlert) { alert in
                switch alert {
                case .missingVideo:
                    return Alert(
                        title: Text("Unable to Share Drill Video"),
                        message: Text("Drill video file is missing or could not be shared."),
                        dismissButton: .default(Text("OK"))
                    )
                case .largeVideo(let videoURLs):
                    return Alert(
                        title: Text("Large Video File"),
                        message: Text("This video may be too large for Email. Try WhatsApp, AirDrop, or Messages."),
                        primaryButton: .default(Text("Continue to Share")) {
                            presentShareSheet(includeMedia: true, videoURLs: videoURLs)
                        },
                        secondaryButton: .cancel()
                    )
                }
            }
        }
    }

    private func emailLessonSummary() {
        let recipient = studentEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recipient.isEmpty else {
            emailStatusMessage = String(localized: "No email address is saved for \(studentName).")
            isShowingEmailStatus = true
            return
        }

        guard MFMailComposeViewController.canSendMail() else {
            emailStatusMessage = String(localized: "This device cannot send email. Set up Mail on an iPhone and try again.")
            isShowingEmailStatus = true
            return
        }

        isShowingEmailComposer = true
    }

    private func shareSummaryWithMedia() {
        let videoFileNames = note.assignedDrills.compactMap { drill -> String? in
            guard let fileName = drill.demoVideoFileName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !fileName.isEmpty else {
                return nil
            }
            return fileName
        }
        let videoURLs = videoFileNames.compactMap(VideoFileStore.storedVideoURL(fileName:))

        guard videoURLs.count == videoFileNames.count else {
            mediaShareAlert = .missingVideo
            return
        }

        if totalFileSize(of: videoURLs) > 20 * 1024 * 1024 {
            mediaShareAlert = .largeVideo(videoURLs)
        } else {
            presentShareSheet(includeMedia: true, videoURLs: videoURLs)
        }
    }

    private func presentShareSheet(includeMedia: Bool, videoURLs: [URL] = []) {
        let image = renderNotesAsImage(formattedText)
        let source = NoteShareItemSource(text: formattedText, image: image)
        var activityItems: [Any] = [source]
        if includeMedia {
            let images = note.imageAttachments
                .sorted { $0.createdAt < $1.createdAt }
                .compactMap { UIImage(data: $0.imageData) }
            activityItems.append(contentsOf: images)
            activityItems.append(contentsOf: videoURLs)
        }
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = scene.windows.first?.rootViewController else { return }
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        if let popover = controller.popoverPresentationController {
            popover.sourceView = topVC.view
            popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        topVC.present(controller, animated: true)
    }

    private func totalFileSize(of urls: [URL]) -> Int {
        urls.reduce(0) { total, url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            return total + (values?.fileSize ?? 0)
        }
    }

    private func renderNotesAsImage(_ text: String) -> UIImage {
        let padding: CGFloat = 24
        let maxWidth: CGFloat = 340
        let titleFont = UIFont.boldSystemFont(ofSize: 15)
        let bodyFont = UIFont.systemFont(ofSize: 14)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 8

        let attributed = NSMutableAttributedString()
        for (i, block) in text.components(separatedBy: "\n\n").enumerated() {
            if i > 0 { attributed.append(NSAttributedString(string: "\n\n")) }
            let isHeader = block == block.uppercased() && !block.contains("\n") && block.count < 40
            let attrs: [NSAttributedString.Key: Any] = [
                .font: isHeader ? titleFont : bodyFont,
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraphStyle
            ]
            attributed.append(NSAttributedString(string: block, attributes: attrs))
        }

        let boundingRect = attributed.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let size = CGSize(width: maxWidth + padding * 2, height: ceil(boundingRect.height) + padding * 2)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            attributed.draw(in: CGRect(x: padding, y: padding, width: maxWidth, height: ceil(boundingRect.height)))
        }
    }
}

// Serves plain text to most apps; serves a rendered image to WeChat (which rejects plain text).
final class NoteShareItemSource: NSObject, UIActivityItemSource {
    private let text: String
    private let image: UIImage

    init(text: String, image: UIImage) {
        self.text = text
        self.image = image
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return image
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        let raw = activityType?.rawValue.lowercased() ?? ""
        if raw.contains("tencent") || raw.contains("wechat") || raw.contains("weixin") {
            return image
        }
        return text
    }
}

struct EditVideoView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var video: LessonVideo
    @State private var title: String
    @State private var lessonDate: Date
    @State private var focusNotes: String
    @State private var problemNotes: String
    @State private var comparisonNotes: String
    @State private var analysisNotes: String

    init(video: LessonVideo) {
        self.video = video
        _title = State(initialValue: video.title)
        _lessonDate = State(initialValue: video.lessonDate ?? video.recordedAt)
        _focusNotes = State(initialValue: video.focusNotes ?? "")
        _problemNotes = State(initialValue: video.problemNotes ?? "")
        _comparisonNotes = State(initialValue: video.comparisonNotes ?? "")
        _analysisNotes = State(initialValue: video.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Lesson Video") {
                    TextField("Title", text: $title)
                    DatePicker("Lesson Date", selection: $lessonDate)
                }

                Section("Progress Notes") {
                    TextField("What the student is improving", text: $focusNotes, axis: .vertical)
                        .lineLimit(3...8)
                    TextField("Existing problem", text: $problemNotes, axis: .vertical)
                        .lineLimit(3...8)
                    TextField("Comparison to last lesson", text: $comparisonNotes, axis: .vertical)
                        .lineLimit(3...8)
                    TextField("Analysis notes", text: $analysisNotes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("Edit Video")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                }
            }
        }
    }

    private func saveChanges() {
        video.title = title
        video.lessonDate = lessonDate
        video.recordedAt = lessonDate
        video.focusNotes = emptyToNil(focusNotes)
        video.problemNotes = emptyToNil(problemNotes)
        video.comparisonNotes = emptyToNil(comparisonNotes)
        video.notes = analysisNotes
    }

    private func emptyToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct DrillLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Drill.title) private var drills: [Drill]
    @Query private var students: [Student]
    @State private var searchText = ""
    @State private var isAddingDrill = false
    @State private var drillForEditing: Drill?
    @State private var drillPendingDeletion: Drill?

    private var filteredDrills: [Drill] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return drills }
        return drills.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.category.localizedCaseInsensitiveContains(query) ||
            $0.purpose.localizedCaseInsensitiveContains(query)
        }
    }

    private var groupedDrills: [(category: String, drills: [Drill])] {
        Dictionary(grouping: filteredDrills) {
            let category = $0.category.trimmingCharacters(in: .whitespacesAndNewlines)
            return category.isEmpty ? String(localized: "Uncategorized") : category
        }
        .map { ($0.key, $0.value.sorted { $0.title < $1.title }) }
        .sorted { $0.category.localizedCaseInsensitiveCompare($1.category) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredDrills.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Drills" : "No Matching Drills",
                        systemImage: "list.bullet.clipboard",
                        description: Text("Create reusable drills to assign as lesson homework.")
                    )
                } else {
                    ForEach(groupedDrills, id: \.category) { group in
                        Section(group.category) {
                            ForEach(group.drills) { drill in
                                DrillLibraryRow(drill: drill) {
                                    drillForEditing = drill
                                } onDelete: {
                                    drillPendingDeletion = drill
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Drill Library")
            .searchable(text: $searchText, prompt: "Search Drills")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAddingDrill = true
                    } label: {
                        Label("Add Drill", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAddingDrill) {
                EditDrillView()
            }
            .sheet(item: $drillForEditing) { drill in
                EditDrillView(drill: drill)
            }
            .alert("Delete Drill", isPresented: Binding(
                get: { drillPendingDeletion != nil },
                set: { if !$0 { drillPendingDeletion = nil } }
            ), presenting: drillPendingDeletion) { drill in
                Button("Delete", role: .destructive) {
                    deleteDrill(drill)
                }
                Button("Cancel", role: .cancel) {
                    drillPendingDeletion = nil
                }
            } message: { drill in
                Text("Delete \(drill.title)? It will be removed from assigned lesson notes.")
            }
        }
    }

    private func deleteDrill(_ drill: Drill) {
        for student in students {
            for note in student.sessionNotes {
                note.assignedDrills.removeAll { $0.persistentModelID == drill.persistentModelID }
            }
        }
        VideoFileStore.deleteStoredVideoFile(fileName: drill.demoVideoFileName)
        modelContext.delete(drill)
        drillPendingDeletion = nil
    }
}

struct DrillLibraryRow: View {
    let drill: Drill
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let imageData = drill.imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "figure.golf")
                    .font(.title3)
                    .frame(width: 52, height: 52)
                    .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(drill.title.isEmpty ? String(localized: "Untitled Drill") : drill.title)
                    .font(.headline)
                if !drill.purpose.isEmpty {
                    Text(drill.purpose)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if drill.demoVideoFileName != nil {
                    Label("Demo Video Attached", systemImage: "video")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Menu {
                Button("Edit", action: onEdit)
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .padding(.vertical, 3)
    }
}

private struct DrillVideoImport: Transferable {
    let storedURL: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { receivedFile in
            let storedURL = try VideoFileStore.copyVideo(from: receivedFile.file)
            return DrillVideoImport(storedURL: storedURL)
        }
    }
}

struct EditDrillView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let drill: Drill?
    @State private var title: String
    @State private var category: String
    @State private var purpose: String
    @State private var instructions: String
    @State private var recommendedReps: String
    @State private var coachTips: String
    @State private var pendingDemoVideoFileName: String?
    @State private var imageData: Data?
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var selectedImageItem: PhotosPickerItem?
    @State private var mediaError: String?
    @State private var isImportingDemoVideo = false

    init(drill: Drill? = nil) {
        self.drill = drill
        _title = State(initialValue: drill?.title ?? "")
        _category = State(initialValue: drill?.category ?? "")
        _purpose = State(initialValue: drill?.purpose ?? "")
        _instructions = State(initialValue: drill?.instructions ?? "")
        _recommendedReps = State(initialValue: drill?.recommendedReps ?? "")
        _coachTips = State(initialValue: drill?.coachTips ?? "")
        _pendingDemoVideoFileName = State(initialValue: drill?.demoVideoFileName)
        _imageData = State(initialValue: drill?.imageData)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Drill Information") {
                    TextField("Title", text: $title)
                    TextField("Category", text: $category)
                    TextField("Purpose", text: $purpose, axis: .vertical)
                        .lineLimit(2...5)
                    TextField("Recommended Reps", text: $recommendedReps)
                }

                Section("Instructions") {
                    TextField("Instructions", text: $instructions, axis: .vertical)
                        .lineLimit(3...8)
                    TextField("Coach Tips", text: $coachTips, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section("Demo Media") {
                    PhotosPicker(
                        selection: $selectedVideoItem,
                        matching: .videos,
                        preferredItemEncoding: .current
                    ) {
                        Label("Attach Demo Video", systemImage: "video.badge.plus")
                    }
                    if isImportingDemoVideo {
                        ProgressView("Importing Demo Video...")
                    }
                    if let demoVideoURL {
                        VideoPlayer(player: AVPlayer(url: demoVideoURL))
                            .frame(height: 190)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Label("Demo Video Attached", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                        Button("Remove Demo Video", role: .destructive) {
                            clearPendingDemoVideo()
                        }
                    }

                    PhotosPicker(selection: $selectedImageItem, matching: .images) {
                        Label("Attach Drill Image", systemImage: "photo.badge.plus")
                    }
                    if let imageData, let image = UIImage(data: imageData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Button("Remove Image", role: .destructive) {
                            self.imageData = nil
                        }
                    }

                    if let mediaError {
                        Text(mediaError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(drill == nil ? "New Drill" : "Edit Drill")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(hasUnsavedImportedVideo)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        discardImportedVideoIfNeeded()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: selectedVideoItem) { _, item in
                guard let item else { return }
                Task {
                    isImportingDemoVideo = true
                    mediaError = nil
                    do {
                        guard let importedVideo = try await item.loadTransferable(type: DrillVideoImport.self) else {
                            throw CocoaError(.fileReadUnknown)
                        }
                        replacePendingDemoVideo(with: VideoFileStore.persistedFileName(for: importedVideo.storedURL))
                    } catch {
                        mediaError = error.localizedDescription
                    }
                    isImportingDemoVideo = false
                    selectedVideoItem = nil
                }
            }
            .onChange(of: selectedImageItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        imageData = LessonNoteAttachmentImageProcessor.compressedData(from: image)
                    }
                    selectedImageItem = nil
                }
            }
        }
    }

    private var hasUnsavedImportedVideo: Bool {
        pendingDemoVideoFileName != drill?.demoVideoFileName
    }

    private var demoVideoURL: URL? {
        guard let pendingDemoVideoFileName else { return nil }
        return VideoFileStore.storedVideoURL(fileName: pendingDemoVideoFileName)
    }

    private func replacePendingDemoVideo(with fileName: String) {
        if let pendingDemoVideoFileName, pendingDemoVideoFileName != drill?.demoVideoFileName {
            VideoFileStore.deleteStoredVideoFile(fileName: pendingDemoVideoFileName)
        }
        pendingDemoVideoFileName = fileName
    }

    private func clearPendingDemoVideo() {
        if let pendingDemoVideoFileName, pendingDemoVideoFileName != drill?.demoVideoFileName {
            VideoFileStore.deleteStoredVideoFile(fileName: pendingDemoVideoFileName)
        }
        pendingDemoVideoFileName = nil
    }

    private func discardImportedVideoIfNeeded() {
        if let pendingDemoVideoFileName, pendingDemoVideoFileName != drill?.demoVideoFileName {
            VideoFileStore.deleteStoredVideoFile(fileName: pendingDemoVideoFileName)
        }
    }

    private func save() {
        let oldVideoFileName = drill?.demoVideoFileName
        let savedDrill = drill ?? Drill()
        savedDrill.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        savedDrill.category = category.trimmingCharacters(in: .whitespacesAndNewlines)
        savedDrill.purpose = purpose
        savedDrill.instructions = instructions
        savedDrill.recommendedReps = recommendedReps
        savedDrill.coachTips = coachTips
        savedDrill.demoVideoFileName = pendingDemoVideoFileName
        savedDrill.imageData = imageData

        if drill == nil {
            modelContext.insert(savedDrill)
        } else if oldVideoFileName != pendingDemoVideoFileName {
            VideoFileStore.deleteStoredVideoFile(fileName: oldVideoFileName)
        }
        dismiss()
    }
}

struct AddPackageView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var student: Student
    @State private var packageType = LessonPackageType.fiveLesson
    @State private var lessonsPurchased = 5
    @State private var totalPaid = 0.0
    @State private var purchaseDate = Date.now
    @State private var paymentMethod = PaymentMethod.creditCard
    @State private var hasSavedPackage = false
    @State private var emailRecipients: [String] = []
    @State private var emailBody = ""
    @State private var isShowingEmailComposer = false
    @State private var isConfirmingEmail = false
    @State private var saveStatusMessage: String?
    @State private var isShowingSaveStatus = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Package", selection: $packageType) {
                    ForEach(LessonPackageType.allCases) { type in
                        Text(type.localizedName).tag(type)
                    }
                }
                .onChange(of: packageType) { _, newValue in
                    switch newValue {
                    case .single:
                        lessonsPurchased = 1
                    case .fiveLesson:
                        lessonsPurchased = 5
                    case .tenLesson:
                        lessonsPurchased = 10
                    case .custom:
                        break
                    }
                }

                Stepper("Lessons: \(lessonsPurchased)", value: $lessonsPurchased, in: 1...100)
                TextField("Total Paid", value: $totalPaid, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                    .keyboardType(.decimalPad)
                Picker("Payment Method", selection: $paymentMethod) {
                    ForEach(PaymentMethod.allCases) { method in
                        Text(method.localizedName).tag(method)
                    }
                }
                DatePicker("Purchase Date", selection: $purchaseDate, displayedComponents: .date)
            }
            .navigationTitle("New Payment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        savePackageAndEmailBalance()
                    }
                    .disabled(hasSavedPackage)
                }
            }
            .sheet(isPresented: $isShowingEmailComposer) {
                LessonEmailComposerView(
                    recipients: emailRecipients,
                    subject: "Golf Coach Payment Confirmation",
                    body: emailBody,
                    onFinish: { _ in
                        dismiss()
                    }
                )
            }
            .alert("Send Confirmation Email?", isPresented: $isConfirmingEmail) {
                Button("Send Email") {
                    preparePaymentEmail()
                }
                Button("Not Now", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text("The payment has been saved. Would you like to email the updated account statement to \(student.name)?")
            }
            .alert("Payment Saved", isPresented: $isShowingSaveStatus, presenting: saveStatusMessage) { _ in
                Button("OK", role: .cancel) {
                    dismiss()
                }
            } message: { message in
                Text(message)
            }
        }
    }

    private func savePackageAndEmailBalance() {
        guard !hasSavedPackage else { return }

        let package = LessonPackage(
            packageType: packageType,
            lessonsPurchased: lessonsPurchased,
            totalPaid: Decimal(totalPaid),
            purchaseDate: purchaseDate,
            paymentMethod: paymentMethod
        )
        student.packages.append(package)
        hasSavedPackage = true

        let email = student.email.trimmingCharacters(in: .whitespacesAndNewlines)
        emailRecipients = [email]
        emailBody = StudentAccountStatementFormatter.message(for: student)
        isConfirmingEmail = true
    }

    private func preparePaymentEmail() {
        let email = student.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else {
            saveStatusMessage = String(localized: "Payment saved, but \(student.name) has no email address on file.")
            isShowingSaveStatus = true
            return
        }

        guard MFMailComposeViewController.canSendMail() else {
            saveStatusMessage = String(localized: "Payment saved, but this device cannot send email. Set up Mail on an iPhone and try again.")
            isShowingSaveStatus = true
            return
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            isShowingEmailComposer = true
        }
    }
}

struct AddLessonView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var student: Student
    @State private var title = "Golf Lesson"
    @State private var scheduledAt = Date.now.addingTimeInterval(60 * 60)
    @State private var durationMinutes = 60
    @State private var location = ""
    @State private var notes = ""
    @State private var reminderLeadTime = ReminderLeadTime.oneDay

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                DatePicker("Date and Time", selection: $scheduledAt)
                Stepper("Duration: \(durationMinutes) min", value: $durationMinutes, in: 15...240, step: 15)
                TextField("Location", text: $location)
                Picker("Reminder", selection: $reminderLeadTime) {
                    ForEach(ReminderLeadTime.allCases) { leadTime in
                        Text(leadTime.rawValue).tag(leadTime)
                    }
                }
                TextField("Lesson notes", text: $notes, axis: .vertical)
                    .lineLimit(3...8)
            }
            .navigationTitle("Schedule Lesson")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let lesson = LessonAppointment(
                            title: title,
                            scheduledAt: scheduledAt,
                            durationMinutes: durationMinutes,
                            location: location,
                            notes: notes,
                            reminderLeadTime: reminderLeadTime
                        )
                        student.lessons.append(lesson)
                        Task {
                            lesson.notificationIdentifier = await LessonReminderScheduler.schedule(student: student, lesson: lesson)
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}

struct LessonVideoImport: Transferable {
    let storedURL: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { receivedFile in
            let storedURL = try VideoFileStore.copyVideo(from: receivedFile.file)
            return LessonVideoImport(storedURL: storedURL)
        }
    }
}

struct AddVideoView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var student: Student
    @State private var lessonDate = Date.now
    @State private var showCamera = false
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var pendingVideoURL: URL?
    @State private var importError: String?
    @State private var isImportingVideo = false
    @State private var isSavingVideo = false
    @State private var savedPendingVideo = false

    init(student: Student, defaultDate: Date = .now) {
        self.student = student
        _lessonDate = State(initialValue: defaultDate)
    }

    var autoTitle: String {
        "Lesson Video — \(lessonDate.formatted(date: .abbreviated, time: .omitted))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Lesson Date", selection: $lessonDate, displayedComponents: .date)
                }

                Section("Video") {
                    Button {
                        if let issue = VideoCaptureReadiness.blockingIssue {
                            importError = issue
                        } else {
                            showCamera = true
                        }
                    } label: {
                        Label("Capture Video", systemImage: "camera")
                    }

                    PhotosPicker(
                        selection: $selectedVideoItem,
                        matching: .videos,
                        preferredItemEncoding: .current
                    ) {
                        Label("Import from Photos", systemImage: "photo.on.rectangle")
                    }
                    .disabled(isImportingVideo || isSavingVideo)

                    if let pendingVideoURL {
                        Label(pendingVideoURL.lastPathComponent, systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    }

                    if isImportingVideo {
                        ProgressView("Importing video...")
                    }

                    if let importError {
                        Text(importError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Video")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        discardPendingVideoIfNeeded()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveVideo()
                    }
                    .disabled(pendingVideoURL == nil || isImportingVideo || isSavingVideo)
                }
            }
            .sheet(isPresented: $showCamera) {
                VideoCaptureView { url in
                    do {
                        let storedURL = try VideoFileStore.copyVideo(from: url)
                        replacePendingVideo(with: storedURL)
                        Task {
                            await VideoFileStore.logVideoImport(url: storedURL, source: "camera picker")
                        }
                    } catch {
                        print("DEBUG LessonVideo camera import failed: fileURL=\(url.path) error=\(error.localizedDescription)")
                        importError = VideoFileStore.importFailureMessage(error)
                    }
                }
            }
            .onChange(of: selectedVideoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    isImportingVideo = true
                    defer { isImportingVideo = false }
                    do {
                        guard let importedVideo = try await newItem.loadTransferable(type: LessonVideoImport.self) else {
                            throw CocoaError(.fileReadUnknown)
                        }
                        replacePendingVideo(with: importedVideo.storedURL)
                        await VideoFileStore.logVideoImport(url: importedVideo.storedURL, source: "PhotosPicker movie")
                    } catch {
                        print("DEBUG LessonVideo PhotosPicker import failed: type=movie fileURL=unavailable error=\(error.localizedDescription)")
                        importError = VideoFileStore.importFailureMessage(error)
                    }
                }
            }
            .onDisappear {
                discardPendingVideoIfNeeded()
            }
        }
    }

    private func replacePendingVideo(with url: URL) {
        if let pendingVideoURL, pendingVideoURL != url, !savedPendingVideo {
            VideoFileStore.deleteStoredVideoFile(fileName: VideoFileStore.persistedFileName(for: pendingVideoURL))
        }
        self.pendingVideoURL = url
        importError = nil
    }

    private func saveVideo() {
        guard !isSavingVideo, let pendingVideoURL else { return }
        isSavingVideo = true

        let fileName = VideoFileStore.persistedFileName(for: pendingVideoURL)
        guard !LessonVideoDisplayStore.containsVideo(in: student.videos, matchingFileURL: pendingVideoURL),
              !LessonVideoDisplayStore.containsVideo(in: student.videos, matchingFileName: fileName),
              !LessonVideoDisplayStore.containsVideo(in: student.videos, matchingContentOf: pendingVideoURL) else {
            print("DEBUG LessonVideo save ignored duplicate record: fileURL=\(pendingVideoURL.path)")
            savedPendingVideo = true
            dismiss()
            return
        }

        let video = LessonVideo(
            title: autoTitle,
            recordedAt: lessonDate,
            fileURLString: fileName,
            lessonDate: lessonDate
        )
        student.videos.append(video)
        savedPendingVideo = true
        print("DEBUG LessonVideo saved id=\(video.persistentModelID) path=\(pendingVideoURL.path) created=\(video.recordedAt)")
        dismiss()
    }

    private func discardPendingVideoIfNeeded() {
        guard !savedPendingVideo, let pendingVideoURL else { return }
        VideoFileStore.deleteStoredVideoFile(fileName: VideoFileStore.persistedFileName(for: pendingVideoURL))
        self.pendingVideoURL = nil
    }
}

struct ScheduleView: View {
    @Query(sort: \Student.name) private var students: [Student]

    var lessons: [(student: Student, lesson: LessonAppointment)] {
        students.flatMap { student in
            student.lessons.map { (student, $0) }
        }
        .sorted { $0.lesson.scheduledAt < $1.lesson.scheduledAt }
    }

    var body: some View {
        NavigationStack {
            List {
                if lessons.isEmpty {
                    ContentUnavailableView("No Lessons", systemImage: "calendar", description: Text("Schedule lessons from a student profile."))
                } else {
                    ForEach(lessons, id: \.lesson.persistentModelID) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.student.name)
                                .font(.headline)
                            Text(item.lesson.scheduledAt, format: .dateTime.weekday(.wide).month().day().hour().minute())
                            Text(item.lesson.reminderLeadTime.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Schedule")
        }
    }
}

struct PaymentsView: View {
    @Query(sort: \Student.name) private var students: [Student]
    @State private var studentForPackage: Student?
    @State private var studentForLesson: Student?
    @State private var studentForCharge: Student?
    @State private var packageForCharge: LessonPackage?
    @State private var chargeEmailBody = ""
    @State private var chargeEmailRecipients: [String] = []
    @State private var isShowingChargeEmailComposer = false
    @State private var pendingConfirmationCharge: LessonCharge?
    @State private var studentPendingConfirmationEmail: Student?
    @State private var isConfirmingChargeEmail = false
    @State private var chargeStatusMessage: String?
    @State private var isShowingChargeStatus = false
    @State private var reversalStudent: Student?
    @State private var chargePackagePendingReversal: LessonPackage?
    @State private var chargePendingReversal: LessonCharge?
    @State private var isConfirmingChargeReversal = false
    @State private var isConfirmingFinalChargeReversal = false
    @State private var reversalEmailStudent: Student?
    @State private var isConfirmingReversalEmail = false
    @State private var reversalStatusMessage: String?
    @State private var isShowingReversalStatus = false

    var body: some View {
        NavigationStack {
            List {
                if students.isEmpty {
                    ContentUnavailableView(
                        "No Students",
                        systemImage: "person.2",
                        description: Text("Add a student before tracking payments.")
                    )
                } else {
                    ForEach(students) { student in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(student.name)
                                    .font(.headline)
                                Spacer()
                                Text(CurrencyFormatter.string(from: student.remainingValue))
                                    .font(.subheadline.weight(.semibold))
                            }

                            HStack {
                                Text("Paid: \(CurrencyFormatter.string(from: student.totalPaid))")
                                Spacer()
                                Text("Balance: \(CurrencyFormatter.string(from: student.remainingValue))")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            HStack {
                                Button {
                                    studentForPackage = student
                                } label: {
                                    Label("Add Payment", systemImage: "creditcard")
                                }
                                .buttonStyle(.borderless)

                                Spacer()

                                Button {
                                    studentForLesson = student
                                } label: {
                                    Label("Schedule", systemImage: "calendar.badge.plus")
                                }
                                .buttonStyle(.borderless)
                            }
                            .font(.caption.weight(.semibold))

                            if let package = student.activePackage {
                                Button {
                                    studentForCharge = student
                                    packageForCharge = package
                                } label: {
                                    Label("Record Lesson Fee", systemImage: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                                .font(.caption.weight(.semibold))
                            }

                            if let latestPackage = student.packages.sorted(by: { $0.purchaseDate > $1.purchaseDate }).first,
                               let latestCharge = latestPackage.charges.sorted(by: { $0.chargedAt > $1.chargedAt }).first {
                                Button(role: .destructive) {
                                    reversalStudent = student
                                    chargePackagePendingReversal = latestPackage
                                    chargePendingReversal = latestCharge
                                    isConfirmingChargeReversal = true
                                } label: {
                                    Label("Restore Latest Fee", systemImage: "arrow.uturn.backward.circle")
                                }
                                .buttonStyle(.borderless)
                                .font(.caption.weight(.semibold))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Payments")
            .sheet(item: $studentForPackage) { student in
                AddPackageView(student: student)
            }
            .sheet(item: $studentForLesson) { student in
                AddLessonView(student: student)
            }
            .sheet(item: $packageForCharge, onDismiss: {
                studentForCharge = nil
            }) { package in
                LogSessionChargeView(package: package) { charge in
                    package.charges.append(charge)
                    package.lessonsUsed += 1
                    studentPendingConfirmationEmail = studentForCharge
                    pendingConfirmationCharge = charge
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(250))
                        guard pendingConfirmationCharge != nil else { return }
                        isConfirmingChargeEmail = true
                    }
                }
            }
            .sheet(isPresented: $isShowingChargeEmailComposer) {
                LessonEmailComposerView(
                    recipients: chargeEmailRecipients,
                    subject: "Golf Lesson Account Statement",
                    body: chargeEmailBody,
                    onFinish: { resultMessage in
                        if let resultMessage {
                            chargeStatusMessage = resultMessage
                            isShowingChargeStatus = true
                        }
                    }
                )
            }
            .alert(
                "Send Confirmation Email?",
                isPresented: $isConfirmingChargeEmail,
                presenting: pendingConfirmationCharge
            ) { charge in
                Button("Send Email") {
                    prepareChargeEmail(for: charge)
                    pendingConfirmationCharge = nil
                }
                Button("Not Now", role: .cancel) {
                    pendingConfirmationCharge = nil
                    studentPendingConfirmationEmail = nil
                }
            } message: { _ in
                Text("The lesson fee has been recorded. Would you like to email the updated account statement to \(studentPendingConfirmationEmail?.name ?? "the student")?")
            }
            .alert("Lesson Update", isPresented: $isShowingChargeStatus, presenting: chargeStatusMessage) { _ in
                Button("OK", role: .cancel) { }
            } message: { message in
                Text(message)
            }
            .alert(
                "Restore Latest Deducted Fee",
                isPresented: $isConfirmingChargeReversal,
                presenting: chargePendingReversal
            ) { charge in
                Button("Continue", role: .destructive) {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(150))
                        guard chargePendingReversal != nil else { return }
                        isConfirmingFinalChargeReversal = true
                    }
                }
                Button("Cancel", role: .cancel) {
                    chargePendingReversal = nil
                    chargePackagePendingReversal = nil
                    reversalStudent = nil
                }
            } message: { charge in
                Text("Remove the lesson charge of \(CurrencyFormatter.string(from: charge.amount)) from \(charge.chargedAt.formatted(date: .abbreviated, time: .omitted))? The credit will be restored.")
            }
            .alert(
                "Final Confirmation",
                isPresented: $isConfirmingFinalChargeReversal,
                presenting: chargePendingReversal
            ) { charge in
                Button("Restore Deducted Fee", role: .destructive) {
                    reverseLessonCharge(charge)
                }
                Button("Cancel", role: .cancel) {
                    chargePendingReversal = nil
                    chargePackagePendingReversal = nil
                    reversalStudent = nil
                }
            } message: { charge in
                Text("Are you sure? This removes the recorded lesson fee of \(CurrencyFormatter.string(from: charge.amount)) and returns that amount to the student's balance.")
            }
            .alert("Send Confirmation Email?", isPresented: $isConfirmingReversalEmail, presenting: reversalEmailStudent) { _ in
                Button("Send Email") {
                    prepareReversalEmail()
                }
                Button("Not Now", role: .cancel) {
                    reversalEmailStudent = nil
                }
            } message: { student in
                Text("The lesson fee has been restored. Would you like to email the updated account statement to \(student.name)?")
            }
            .alert("Reversal Complete", isPresented: $isShowingReversalStatus, presenting: reversalStatusMessage) { _ in
                Button("OK", role: .cancel) { }
            } message: { message in
                Text(message)
            }
        }
    }

    private func prepareChargeEmail(for charge: LessonCharge) {
        guard let student = studentPendingConfirmationEmail ?? studentForCharge else { return }
        chargeEmailBody = StudentAccountStatementFormatter.message(
            for: student,
            latestCharge: charge
        )
        let email = student.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else {
            chargeStatusMessage = String(localized: "Session charge saved, but \(student.name) has no email address on file.")
            isShowingChargeStatus = true
            studentPendingConfirmationEmail = nil
            return
        }
        guard MFMailComposeViewController.canSendMail() else {
            chargeStatusMessage = String(localized: "Session charge saved, but this device cannot send email. Set up Mail on an iPhone and try again.")
            isShowingChargeStatus = true
            studentPendingConfirmationEmail = nil
            return
        }

        chargeEmailRecipients = [email]
        studentPendingConfirmationEmail = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            isShowingChargeEmailComposer = true
        }
    }

    private func prepareReversalEmail() {
        guard let student = reversalEmailStudent else { return }
        chargeEmailBody = StudentAccountStatementFormatter.message(for: student)
        let email = student.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else {
            chargeStatusMessage = String(localized: "Lesson fee restored, but \(student.name) has no email address on file.")
            isShowingChargeStatus = true
            reversalEmailStudent = nil
            return
        }
        guard MFMailComposeViewController.canSendMail() else {
            chargeStatusMessage = String(localized: "Lesson fee restored, but this device cannot send email. Set up Mail on an iPhone and try again.")
            isShowingChargeStatus = true
            reversalEmailStudent = nil
            return
        }

        chargeEmailRecipients = [email]
        reversalEmailStudent = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            isShowingChargeEmailComposer = true
        }
    }

    private func reverseLessonCharge(_ charge: LessonCharge) {
        guard let student = reversalStudent,
              let package = chargePackagePendingReversal,
              package.charges.contains(where: { $0.persistentModelID == charge.persistentModelID }) else {
            chargePendingReversal = nil
            chargePackagePendingReversal = nil
            reversalStudent = nil
            isConfirmingFinalChargeReversal = false
            return
        }

        package.charges.removeAll { $0.persistentModelID == charge.persistentModelID }
        package.lessonsUsed = max(package.lessonsUsed - 1, 0)
        reversalEmailStudent = student
        chargePendingReversal = nil
        chargePackagePendingReversal = nil
        reversalStudent = nil
        isConfirmingFinalChargeReversal = false
        reversalStatusMessage = "Lesson charge reversed. \(student.name) now has \(CurrencyFormatter.string(from: student.remainingValue)) remaining."
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard reversalEmailStudent != nil else { return }
            isConfirmingReversalEmail = true
        }
    }
}

struct VideoLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Student.name) private var students: [Student]
    let onPlayVideo: (LessonVideo, Student) -> Void

    var videos: [(student: Student, video: LessonVideo)] {
        students.flatMap { student in
            LessonVideoDisplayStore.uniqueVideos(in: student.videos).map { (student, $0) }
        }
        .sorted { $0.video.recordedAt > $1.video.recordedAt }
    }

    var body: some View {
        NavigationStack {
            List {
                if videos.isEmpty {
                    ContentUnavailableView("No Videos", systemImage: "video", description: Text("Capture or import videos from a student profile."))
                } else {
                    ForEach(videos, id: \.video.persistentModelID) { item in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.video.title)
                                    .font(.headline)
                                Text(item.student.name)
                                    .foregroundStyle(.secondary)
                                Text(item.video.recordedAt, format: .dateTime.month().day().year())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let url = item.video.fileURL {
                                Button {
                                    openVideo(item.video, student: item.student)
                                } label: {
                                    Image(systemName: "play.circle")
                                }
                                .buttonStyle(.borderless)

                                ShareLink(item: url) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: deleteVideos)
                }
            }
            .navigationTitle("Videos")
        }
    }

    private func openVideo(_ video: LessonVideo, student: Student) {
        guard video.fileURL != nil else {
            print("DEBUG VideoLibraryView selectedVideo ignored missing file: \(video.title)")
            return
        }

        print("DEBUG VideoLibraryView requested selectedVideo: \(video.title)")
        onPlayVideo(video, student)
    }

    private func deleteVideos(at offsets: IndexSet) {
        for index in offsets {
            let item = videos[index]
            deleteVideo(item.video, from: item.student)
        }
    }

    private func deleteVideo(_ video: LessonVideo, from student: Student) {
        VideoFileStore.deleteStoredVideoFile(for: video)
        student.videos.removeAll { $0.persistentModelID == video.persistentModelID }
        modelContext.delete(video)
    }
}

struct VideoPlaybackSelection: Identifiable {
    let video: LessonVideo
    let studentName: String
    let student: Student?

    var id: PersistentIdentifier {
        video.persistentModelID
    }
}

struct CoachAnalysisPlaybackSelection: Identifiable {
    let analysis: CoachAnalysisVideo

    var id: PersistentIdentifier {
        analysis.persistentModelID
    }
}

enum SwingDrawingTool: String, CaseIterable, Codable, Identifiable {
    case line = "Line"
    case circle = "Circle"
    case freehand = "Freehand"

    var id: String { rawValue }
}

enum SwingDrawingColor: String, CaseIterable, Codable, Identifiable {
    case yellow
    case red
    case green
    case blue
    case white

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .yellow:
            return .yellow
        case .red:
            return .red
        case .green:
            return .green
        case .blue:
            return .blue
        case .white:
            return .white
        }
    }

    var uiColor: UIColor {
        switch self {
        case .yellow:
            return .systemYellow
        case .red:
            return .systemRed
        case .green:
            return .systemGreen
        case .blue:
            return .systemBlue
        case .white:
            return .white
        }
    }
}

struct SwingAnalysisStroke: Codable, Identifiable {
    var id = UUID()
    var points: [CGPoint]
    var tool: SwingDrawingTool?
    var color: SwingDrawingColor?

    var drawingTool: SwingDrawingTool {
        tool ?? .line
    }

    var drawingColor: SwingDrawingColor {
        color ?? .yellow
    }
}

struct SwingDrawingOverlay: View {
    @Binding var strokes: [SwingAnalysisStroke]
    @Binding var currentStroke: SwingAnalysisStroke?
    @Binding var selectedTool: SwingDrawingTool
    @Binding var selectedColor: SwingDrawingColor
    let isDrawingEnabled: Bool
    let onUndo: () -> Void
    var onZoomBegan: () -> Void = { }
    var onZoomChanged: (CGFloat) -> Void = { _ in }
    var onZoomEnded: () -> Void = { }
    var onZoomPanBegan: () -> Void = { }
    var onZoomPanChanged: (CGSize) -> Void = { _ in }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.clear

                ForEach(strokes) { stroke in
                    strokeShape(stroke, in: proxy.size)
                        .stroke(stroke.drawingColor.color, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                        .shadow(color: .black.opacity(0.7), radius: 1)
                }

                if let currentStroke {
                    strokeShape(currentStroke, in: proxy.size)
                        .stroke(currentStroke.drawingColor.color, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                        .shadow(color: .black.opacity(0.7), radius: 1)
                }

                DrawingGestureCapture(
                    strokes: $strokes,
                    currentStroke: $currentStroke,
                    selectedTool: selectedTool,
                    selectedColor: selectedColor,
                    isDrawingEnabled: isDrawingEnabled,
                    onZoomBegan: onZoomBegan,
                    onZoomChanged: onZoomChanged,
                    onZoomEnded: onZoomEnded,
                    onZoomPanBegan: onZoomPanBegan,
                    onZoomPanChanged: onZoomPanChanged
                )
            }
            .contentShape(Rectangle())
            .allowsHitTesting(isDrawingEnabled)
        }
    }

    private func strokeShape(_ stroke: SwingAnalysisStroke, in size: CGSize) -> Path {
        switch stroke.drawingTool {
        case .line:
            return linePath(stroke, in: size)
        case .circle:
            return circlePath(stroke, in: size)
        case .freehand:
            return linePath(stroke, in: size)
        }
    }

    private func linePath(_ stroke: SwingAnalysisStroke, in size: CGSize) -> Path {
        var path = Path()
        guard let firstPoint = stroke.points.first, let lastPoint = stroke.points.last else { return path }
        path.move(to: denormalizedPoint(firstPoint, in: size))
        path.addLine(to: denormalizedPoint(lastPoint, in: size))
        return path
    }

    private func circlePath(_ stroke: SwingAnalysisStroke, in size: CGSize) -> Path {
        guard let firstPoint = stroke.points.first, let lastPoint = stroke.points.last else { return Path() }
        let start = denormalizedPoint(firstPoint, in: size)
        let end = denormalizedPoint(lastPoint, in: size)
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(start.x - end.x),
            height: abs(start.y - end.y)
        )
        return Path(ellipseIn: rect)
    }

    private func normalizedPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: max(0, min(point.x / max(size.width, 1), 1)),
            y: max(0, min(point.y / max(size.height, 1), 1))
        )
    }

    private func denormalizedPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }
}

struct DrawingGestureCapture: UIViewRepresentable {
    @Binding var strokes: [SwingAnalysisStroke]
    @Binding var currentStroke: SwingAnalysisStroke?
    let selectedTool: SwingDrawingTool
    let selectedColor: SwingDrawingColor
    let isDrawingEnabled: Bool
    let onZoomBegan: () -> Void
    let onZoomChanged: (CGFloat) -> Void
    let onZoomEnded: () -> Void
    let onZoomPanBegan: () -> Void
    let onZoomPanChanged: (CGSize) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true

        let oneFingerPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleOneFingerPan(_:)))
        oneFingerPan.minimumNumberOfTouches = 1
        oneFingerPan.maximumNumberOfTouches = 1
        oneFingerPan.cancelsTouchesInView = true
        oneFingerPan.delegate = context.coordinator
        view.addGestureRecognizer(oneFingerPan)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.cancelsTouchesInView = true
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)

        let twoFingerPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTwoFingerPan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        twoFingerPan.cancelsTouchesInView = true
        twoFingerPan.delegate = context.coordinator
        view.addGestureRecognizer(twoFingerPan)

        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
        view.isUserInteractionEnabled = isDrawingEnabled
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: DrawingGestureCapture
        private var strokeStartPoint: CGPoint?

        init(parent: DrawingGestureCapture) {
            self.parent = parent
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard parent.isDrawingEnabled else { return false }
            if gestureRecognizer is UIPinchGestureRecognizer {
                return gestureRecognizer.numberOfTouches >= 2
            }

            if gestureRecognizer is UIPanGestureRecognizer {
                return gestureRecognizer.numberOfTouches == 1 || gestureRecognizer.numberOfTouches == 2
            }

            return false
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer is UIPinchGestureRecognizer || otherGestureRecognizer is UIPinchGestureRecognizer
        }

        @objc func handleOneFingerPan(_ gesture: UIPanGestureRecognizer) {
            guard parent.isDrawingEnabled,
                  let view = gesture.view else {
                return
            }

            let point = normalizedPoint(gesture.location(in: view), in: view.bounds.size)
            switch gesture.state {
            case .began:
                strokeStartPoint = point
                let tool = parent.selectedTool == .freehand ? .line : parent.selectedTool
                parent.currentStroke = SwingAnalysisStroke(points: [point, point], tool: tool, color: parent.selectedColor)
            case .changed:
                guard let strokeStartPoint else { return }
                switch parent.selectedTool {
                case .line, .circle, .freehand:
                    parent.currentStroke?.points = [strokeStartPoint, point]
                }
            case .ended:
                commitStroke(in: view.bounds.size)
            case .cancelled, .failed:
                resetStroke()
            default:
                break
            }
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard parent.isDrawingEnabled else { return }

            switch gesture.state {
            case .began:
                parent.onZoomBegan()
            case .changed:
                parent.onZoomChanged(gesture.scale)
            case .ended, .cancelled, .failed:
                parent.onZoomEnded()
            default:
                break
            }
        }

        @objc func handleTwoFingerPan(_ gesture: UIPanGestureRecognizer) {
            guard parent.isDrawingEnabled else { return }

            switch gesture.state {
            case .began:
                parent.onZoomPanBegan()
            case .changed:
                let translation = gesture.translation(in: gesture.view)
                parent.onZoomPanChanged(CGSize(width: translation.x, height: translation.y))
            case .ended, .cancelled, .failed:
                parent.onZoomEnded()
            default:
                break
            }
        }

        private func commitStroke(in size: CGSize) {
            guard let stroke = parent.currentStroke else {
                resetStroke()
                return
            }

            if shouldCommit(stroke, in: size) {
                parent.strokes.append(stroke)
            }
            resetStroke()
        }

        private func resetStroke() {
            parent.currentStroke = nil
            strokeStartPoint = nil
        }

        private func normalizedPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
            CGPoint(
                x: max(0, min(point.x / max(size.width, 1), 1)),
                y: max(0, min(point.y / max(size.height, 1), 1))
            )
        }

        private func denormalizedPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
            CGPoint(x: point.x * size.width, y: point.y * size.height)
        }

        private func shouldCommit(_ stroke: SwingAnalysisStroke, in size: CGSize) -> Bool {
            guard stroke.points.count > 1,
                  let firstPoint = stroke.points.first,
                  let lastPoint = stroke.points.last else {
                return false
            }

            switch stroke.drawingTool {
            case .freehand:
                fallthrough
            case .line, .circle:
                let start = denormalizedPoint(firstPoint, in: size)
                let end = denormalizedPoint(lastPoint, in: size)
                let distance = hypot(end.x - start.x, end.y - start.y)
                return distance >= 12
            }
        }
    }
}

private struct DrawingTogglePill: View {
    let isActive: Bool
    let selectedColor: SwingDrawingColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "pencil.tip.crop.circle")
                Text("Draw")
                    .font(.caption.weight(.bold))
                Circle()
                    .fill(selectedColor.color)
                    .frame(width: 10, height: 10)
            }
            .frame(height: 34)
            .padding(.horizontal, 12)
        }
        .foregroundStyle(.white)
        .background(isActive ? Color.purple.opacity(0.85) : Color.black.opacity(0.72))
        .clipShape(Capsule())
        .buttonStyle(.plain)
    }
}

struct DrawingToolPalette: View {
    @Binding var selectedTool: SwingDrawingTool
    @Binding var selectedColor: SwingDrawingColor
    let canUndo: Bool
    let onUndo: () -> Void

    var body: some View {
        Menu {
            Button {
                selectedTool = .line
            } label: {
                Label("Straight Line", systemImage: "slash")
            }

            Button {
                selectedTool = .circle
            } label: {
                Label("Circle", systemImage: "circle")
            }

            Button {
                onUndo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!canUndo)

            Divider()

            Picker("Color", selection: $selectedColor) {
                ForEach(SwingDrawingColor.allCases) { color in
                    Label(color.rawValue.capitalized, systemImage: selectedColor == color ? "checkmark.circle.fill" : "circle")
                        .tag(color)
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "pencil.tip.crop.circle")
                Text("Draw")
                    .font(.caption.weight(.bold))
                Circle()
                    .fill(selectedColor.color)
                    .frame(width: 10, height: 10)
            }
            .frame(height: 34)
            .padding(.horizontal, 12)
        }
        .foregroundStyle(.white)
        .background(Color.black.opacity(0.72))
        .clipShape(Capsule())
        .accessibilityLabel("Drawing tools")
    }
}

struct RecordingIndicatorButton: View {
    let onStop: () -> Void
    @State private var isPulsing = false

    var body: some View {
        Button(action: onStop) {
            ZStack {
                Circle()
                    .fill(.red.opacity(isPulsing ? 0.18 : 0.45))
                    .frame(width: 40, height: 40)
                    .scaleEffect(isPulsing ? 1.35 : 1)

                Image(systemName: "stop.circle.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.red)
                    .background(.white, in: Circle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop coach analysis recording")
        .onAppear {
            withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

struct VideoPlayerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let video: LessonVideo
    let studentName: String
    let student: Student?
    @State private var isSavingToPhotos = false
    @State private var saveStatus: VideoSaveStatus?
    @State private var isShowingSaveStatus = false
    @State private var player: AVPlayer?
    @State private var sourceDurationSeconds = 0.0
    @State private var durationSeconds = 0.0
    @State private var sourceFrameRate: Float = 60
    @State private var currentTimeSeconds = 0.0
    @State private var playbackRate: Float = 1.0
    @State private var isPlaying = false
    @State private var isScrubbing = false
    @State private var isShowingInlineTrimControls = false
    @State private var activeTrimStartSeconds = 0.0
    @State private var activeTrimEndSeconds: Double?
    @State private var draftTrimStartSeconds = 0.0
    @State private var draftTrimEndSeconds: Double?
    @State private var isEditingVideo = false
    @State private var isDrawingMode = false
    @State private var selectedDrawingTool = SwingDrawingTool.line
    @State private var selectedDrawingColor = SwingDrawingColor.yellow
    @State private var strokes: [SwingAnalysisStroke] = []
    @State private var currentStroke: SwingAnalysisStroke?
    @State private var annotatedShareURL: URL?
    @State private var isExportingAnnotatedVideo = false
    @State private var trimEndBoundaryObserver: Any?
    @State private var playbackProgressObserver: Any?
    @State private var coachAnalysisRecorder = CoachAnalysisRecorder()
    @State private var isRecordingCoachAnalysis = false
    @State private var isPreparingPlayback = false
    @State private var analysisZoomScale: CGFloat = 1
    @State private var analysisZoomStartScale: CGFloat = 1
    @State private var analysisZoomOffset = CGSize.zero
    @State private var analysisZoomStartOffset = CGSize.zero

    init(video: LessonVideo, studentName: String, student: Student? = nil) {
        self.video = video
        self.studentName = studentName
        self.student = student
        _player = State(initialValue: video.fileURL.map { AVPlayer(url: $0) })
        _strokes = State(initialValue: Self.initialDrawingStrokes(for: video))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let player {
                    GeometryReader { proxy in
                        ZStack(alignment: .top) {
                            ZStack {
                                ControlledVideoPlayer(player: player, showsPlaybackControls: false)
                                    .background(.black)

                                SwingDrawingOverlay(
                                    strokes: $strokes,
                                    currentStroke: $currentStroke,
                                    selectedTool: $selectedDrawingTool,
                                    selectedColor: $selectedDrawingColor,
                                    isDrawingEnabled: isDrawingMode,
                                    onUndo: undoLastStroke,
                                    onZoomBegan: beginAnalysisZoom,
                                    onZoomChanged: { relativeScale in
                                        updateAnalysisZoom(relativeScale: relativeScale, in: proxy.size)
                                    },
                                    onZoomEnded: endAnalysisZoom,
                                    onZoomPanBegan: beginAnalysisZoomPan,
                                    onZoomPanChanged: { translation in
                                        updateAnalysisZoomPan(translation: translation, in: proxy.size)
                                    }
                                )
                            }
                            .scaleEffect(analysisZoomScale)
                            .offset(analysisZoomOffset)
                            .contentShape(Rectangle())
                            .gesture(analysisTransformGesture(in: proxy.size), isEnabled: !isDrawingMode)
                            .onTapGesture(count: 2) {
                                resetAnalysisZoom()
                            }

                            HStack(alignment: .top) {
                                Spacer()

                                if isRecordingCoachAnalysis {
                                    RecordingIndicatorButton {
                                        stopCoachAnalysisRecording()
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                            .frame(maxWidth: .infinity)
                        }
                        .clipped()
                    }
                } else {
                    ContentUnavailableView(
                        "Video Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("This video file could not be found.")
                    )
                }
            }
            .navigationTitle(video.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        saveDrawingStrokes()
                        dismiss()
                    }
                }

                if let url = video.fileURL {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                selectedDrawingTool = .line
                                isDrawingMode = true
                                player?.pause()
                                isPlaying = false
                                saveDrawingStrokes()
                            } label: {
                                Label(selectedDrawingTool == .line && isDrawingMode ? "Line Tool Selected" : "Line Tool", systemImage: selectedDrawingTool == .line && isDrawingMode ? "checkmark" : "line.diagonal")
                            }

                            Button {
                                selectedDrawingTool = .circle
                                isDrawingMode = true
                                player?.pause()
                                isPlaying = false
                                saveDrawingStrokes()
                            } label: {
                                Label(selectedDrawingTool == .circle && isDrawingMode ? "Circle Tool Selected" : "Circle Tool", systemImage: selectedDrawingTool == .circle && isDrawingMode ? "checkmark" : "circle")
                            }

                            if isDrawingMode {
                                Button {
                                    isDrawingMode = false
                                    saveDrawingStrokes()
                                } label: {
                                    Label("Stop Drawing", systemImage: "pencil.slash")
                                }
                            }

                            Button {
                                undoLastStroke()
                            } label: {
                                Label("Undo Last Drawing", systemImage: "arrow.uturn.backward")
                            }
                            .disabled(strokes.isEmpty)

                            Button(role: .destructive) {
                                clearStrokes()
                            } label: {
                                Label("Clear Drawing", systemImage: "trash")
                            }
                            .disabled(strokes.isEmpty)

                            Divider()

                            Button {
                                toggleCoachAnalysisRecording()
                            } label: {
                                Label(
                                    isRecordingCoachAnalysis ? "Stop Coach Analysis Recording" : "Coach Analysis",
                                    systemImage: isRecordingCoachAnalysis ? "stop.circle.fill" : "waveform.path.ecg"
                                )
                            }
                            .disabled(coachAnalysisRecorder.isRecording && !isRecordingCoachAnalysis)

                            Button {
                                self.player?.playImmediately(atRate: playbackRate)
                                isPlaying = true
                            } label: {
                                Label("Play All", systemImage: "play.fill")
                            }

                            Button {
                                self.player?.pause()
                                isPlaying = false
                            } label: {
                                Label("Pause All", systemImage: "pause.fill")
                            }

                            Menu {
                                Button {
                                    setPlaybackRate(0.5)
                                } label: {
                                    Label("0.5x", systemImage: playbackRate == 0.5 ? "checkmark" : "speedometer")
                                }

                                Button {
                                    setPlaybackRate(1.0)
                                } label: {
                                    Label("1.0x", systemImage: playbackRate == 1.0 ? "checkmark" : "speedometer")
                                }
                            } label: {
                                Label("Speed \(playbackRate, specifier: "%.1f")x", systemImage: "speedometer")
                            }

                            Divider()

                            Button {
                                isEditingVideo = true
                            } label: {
                                Label("Edit Notes", systemImage: "pencil")
                            }

                            Button {
                                revertTrim()
                            } label: {
                                Label("Revert Trim", systemImage: "arrow.counterclockwise")
                            }
                            .disabled(!hasActiveTrim)

                            Button {
                                exportAnnotatedVideo(url)
                            } label: {
                                Label("Share Video with Lines", systemImage: "square.and.arrow.up")
                            }
                            .disabled(strokes.isEmpty || isExportingAnnotatedVideo)

                            Button {
                                saveVideoToPhotos(url)
                            } label: {
                                Label("Save to Photos", systemImage: "photo.badge.plus")
                            }
                            .disabled(isSavingToPhotos)

                            ShareLink(item: url) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        } label: {
                            if isSavingToPhotos || isExportingAnnotatedVideo {
                                ProgressView()
                            } else {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    lessonVideoPlaybackControls

                    if isShowingInlineTrimControls && !isRecordingCoachAnalysis {
                        InlineTrimControls(
                            startTime: Binding(
                                get: { draftTrimStartSeconds },
                                set: { value in
                                    draftTrimStartSeconds = max(0, min(clampedTrimStart(value), (draftTrimEndSeconds ?? durationSeconds) - 0.2))
                                }
                            ),
                            endTime: Binding(
                                get: { draftTrimEndSeconds ?? sourceDurationSeconds },
                                set: { value in
                                    draftTrimEndSeconds = clampedTrimEnd(value, minimumStart: draftTrimStartSeconds)
                                }
                            ),
                            duration: sourceDurationSeconds,
                            onHandleMoved: { time in
                                seekToAbsolute(time)
                            },
                            onApply: {
                                applyTrim(startTime: draftTrimStartSeconds, endTime: draftTrimEndSeconds ?? sourceDurationSeconds)
                            }
                        )
                    } else if hasActiveTrim && !isRecordingCoachAnalysis {
                        HStack {
                            Label(
                                "Trimmed \(timeString(playbackStartSeconds)) - \(timeString(playbackEndSeconds))",
                                systemImage: "scissors"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                            Spacer()

                            Button("Revert") {
                                revertTrim()
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }

                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.regularMaterial)
            }
            .alert(saveStatus?.title ?? "Save Video", isPresented: $isShowingSaveStatus) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveStatus?.message ?? "")
            }
            .onAppear {
                updateDuration()
                applyStoredTrimIfNeeded()
                reloadPlayerForCurrentTrim()
                prepareForPlayback()
            }
            .task {
                await trackPlaybackTime()
            }
            .onDisappear {
                saveDrawingStrokes()
                player?.pause()
                removeTrimEndBoundaryObserver()
                removePlaybackProgressObserver()
                if coachAnalysisRecorder.isRecording {
                    stopCoachAnalysisRecording()
                }
            }
            .sheet(isPresented: $isEditingVideo) {
                EditVideoView(video: video)
            }
            .sheet(item: $annotatedShareURL) { url in
                ActivityShareSheet(items: [url])
            }
        }
    }

    private var lessonVideoPlaybackControls: some View {
        HStack(spacing: 10) {
            Button {
                togglePlayback()
            } label: {
                Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isPreparingPlayback)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            Button {
                stepFrame(direction: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Back 1 Frame")

            VStack(spacing: 3) {
                HStack {
                    Text(timeString(currentTimeSeconds))
                    Spacer()
                    Text(timeString(durationSeconds))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

                Slider(
                    value: Binding(
                        get: { currentTimeSeconds },
                        set: { value in
                            currentTimeSeconds = min(max(value, 0), durationSeconds)
                            seek(to: currentTimeSeconds)
                        }
                    ),
                    in: 0...max(durationSeconds, 0.1),
                    onEditingChanged: { editing in
                        if editing {
                            isScrubbing = true
                            player?.pause()
                            isPlaying = false
                        } else {
                            isScrubbing = false
                            seek(to: currentTimeSeconds)
                        }
                    }
                )
            }

            Button {
                stepFrame(direction: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Forward 1 Frame")

            Button {
                player?.pause()
                isPlaying = false
                toggleInlineTrimControls()
            } label: {
                Label("Trim", systemImage: "scissors")
                    .labelStyle(.iconOnly)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isRecordingCoachAnalysis)
            .accessibilityLabel("Trim")
        }
        .font(.caption.weight(.semibold))
    }

    private func toggleCoachAnalysisRecording() {
        if isRecordingCoachAnalysis {
            stopCoachAnalysisRecording()
        } else {
            startCoachAnalysisRecording()
        }
    }

    private func startCoachAnalysisRecording() {
        guard student != nil else {
            saveStatus = VideoSaveStatus(
                title: "Recording Unavailable",
                message: "Open this video from a student profile before recording coach analysis."
            )
            isShowingSaveStatus = true
            return
        }

        isDrawingMode = true
        saveDrawingStrokes()

        Task {
            do {
                try await coachAnalysisRecorder.start()
                isRecordingCoachAnalysis = true
            } catch {
                saveStatus = VideoSaveStatus(title: "Recording Failed", message: error.localizedDescription)
                isShowingSaveStatus = true
            }
        }
    }

    private func stopCoachAnalysisRecording() {
        Task {
            do {
                let outputURL = try await coachAnalysisRecorder.stop()
                isRecordingCoachAnalysis = false
                let analysis = CoachAnalysisVideo(
                    title: "Coach Analysis",
                    recordedAt: .now,
                    fileURLString: VideoFileStore.persistedFileName(for: outputURL),
                    notes: "Analysis for \(video.title)",
                    lessonDate: video.lessonDate ?? video.recordedAt
                )
                student?.coachAnalysisVideos.append(analysis)
                saveStatus = VideoSaveStatus(
                    title: "Analysis Saved",
                    message: "The coach analysis video was saved under this student's profile."
                )
                isShowingSaveStatus = true
            } catch {
                isRecordingCoachAnalysis = false
                saveStatus = VideoSaveStatus(title: "Recording Failed", message: error.localizedDescription)
                isShowingSaveStatus = true
            }
        }
    }

    private func beginAnalysisZoom() {
        analysisZoomStartScale = analysisZoomScale
    }

    private func updateAnalysisZoom(relativeScale: CGFloat, in size: CGSize) {
        analysisZoomScale = min(max(analysisZoomStartScale * relativeScale, 1), 5)
        analysisZoomOffset = clampedAnalysisZoomOffset(analysisZoomOffset, scale: analysisZoomScale, in: size)
    }

    private func endAnalysisZoom() {
        commitAnalysisTransform()
    }

    private func beginAnalysisZoomPan() {
        analysisZoomStartOffset = analysisZoomOffset
    }

    private func updateAnalysisZoomPan(translation: CGSize, in size: CGSize) {
        guard analysisZoomScale > 1 else {
            analysisZoomOffset = .zero
            analysisZoomStartOffset = .zero
            return
        }

        let proposedOffset = CGSize(
            width: analysisZoomStartOffset.width + translation.width,
            height: analysisZoomStartOffset.height + translation.height
        )
        analysisZoomOffset = clampedAnalysisZoomOffset(proposedOffset, scale: analysisZoomScale, in: size)
    }

    private func analysisTransformGesture(in size: CGSize) -> some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    updateAnalysisZoom(relativeScale: value, in: size)
                }
                .onEnded { _ in
                    commitAnalysisTransform()
                },
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    updateAnalysisZoomPan(translation: value.translation, in: size)
                }
                .onEnded { _ in
                    commitAnalysisTransform()
                }
        )
    }

    private func commitAnalysisTransform() {
        analysisZoomScale = min(max(analysisZoomScale, 1), 5)
        analysisZoomOffset = analysisZoomScale <= 1 ? .zero : analysisZoomOffset
        analysisZoomStartScale = analysisZoomScale
        analysisZoomStartOffset = analysisZoomOffset
    }

    private func resetAnalysisZoom() {
        analysisZoomScale = 1
        analysisZoomStartScale = 1
        analysisZoomOffset = .zero
        analysisZoomStartOffset = .zero
    }

    private func clampedAnalysisZoomOffset(_ offset: CGSize, scale: CGFloat, in size: CGSize) -> CGSize {
        guard scale > 1 else { return .zero }

        let horizontalLimit = (size.width * (scale - 1)) / 2
        let verticalLimit = (size.height * (scale - 1)) / 2
        return CGSize(
            width: min(max(offset.width, -horizontalLimit), horizontalLimit),
            height: min(max(offset.height, -verticalLimit), verticalLimit)
        )
    }

    private var playbackStartSeconds: Double {
        clampedTrimStart(video.trimStartSeconds ?? activeTrimStartSeconds)
    }

    private func prepareForPlayback() {
        Task { @MainActor in
            guard let player else { return }

            isPreparingPlayback = true
            player.pause()
            guard await VideoPlaybackReadiness.waitUntilReady(player.currentItem) else {
                isPreparingPlayback = false
                return
            }
            updateDuration()
            await player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            currentTimeSeconds = 0
            isPreparingPlayback = false
        }
    }

    private var playbackEndSeconds: Double {
        clampedTrimEnd(video.trimEndSeconds ?? activeTrimEndSeconds ?? sourceDurationSeconds)
    }

    private var hasActiveTrim: Bool {
        let start = video.trimStartSeconds ?? activeTrimStartSeconds
        let end = video.trimEndSeconds ?? activeTrimEndSeconds
        return start > 0.05 || (end.map { sourceDurationSeconds - $0 > 0.05 } ?? false)
    }

    private static func initialDrawingStrokes(for video: LessonVideo) -> [SwingAnalysisStroke] {
        guard let analysisDrawingData = video.analysisDrawingData,
              let data = analysisDrawingData.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([SwingAnalysisStroke].self, from: data) else {
            return []
        }
        return decoded
    }

    private func saveDrawingStrokes() {
        guard let data = try? JSONEncoder().encode(strokes) else { return }
        video.analysisDrawingData = String(data: data, encoding: .utf8)
    }

    private func undoLastStroke() {
        _ = strokes.popLast()
        saveDrawingStrokes()
    }

    private func clearStrokes() {
        strokes.removeAll()
        video.analysisDrawingData = nil
    }

    private func exportAnnotatedVideo(_ url: URL) {
        saveDrawingStrokes()
        isExportingAnnotatedVideo = true
        Task {
            do {
                annotatedShareURL = try await SwingAnalysisVideoExporter.exportAnnotatedVideo(
                    sourceURL: url,
                    strokes: strokes,
                    startSeconds: playbackStartSeconds,
                    endSeconds: playbackEndSeconds
                )
            } catch {
                saveStatus = .failure(error.localizedDescription)
                isShowingSaveStatus = true
            }
            isExportingAnnotatedVideo = false
        }
    }

    private func updateDuration() {
        let sourceAsset = video.fileURL.map { AVURLAsset(url: $0) }
        let sourceDuration = sourceAsset?.duration.seconds ?? player?.currentItem?.asset.duration.seconds
        guard let sourceDuration, sourceDuration.isFinite else { return }
        sourceDurationSeconds = sourceDuration
        if let frameRate = sourceAsset?.tracks(withMediaType: .video).first?.nominalFrameRate,
           frameRate.isFinite,
           frameRate > 0 {
            sourceFrameRate = frameRate
        }
        durationSeconds = hasActiveTrim ? max(playbackEndSeconds - playbackStartSeconds, 0.1) : sourceDuration
        activeTrimStartSeconds = clampedTrimStart(video.trimStartSeconds ?? activeTrimStartSeconds)
        activeTrimEndSeconds = clampedTrimEnd(video.trimEndSeconds ?? activeTrimEndSeconds ?? sourceDuration)
        draftTrimStartSeconds = activeTrimStartSeconds
        draftTrimEndSeconds = activeTrimEndSeconds
    }

    private func trackPlaybackTime() async {
        while !Task.isCancelled {
            guard !isPreparingPlayback,
                  !isScrubbing,
                  let currentItem = player?.currentItem,
                  currentItem.status == .readyToPlay else {
                try? await Task.sleep(for: .milliseconds(30))
                continue
            }

            let itemDuration = currentItem.duration.seconds
            guard itemDuration.isFinite, itemDuration > 0, durationSeconds > 0 else {
                try? await Task.sleep(for: .milliseconds(30))
                continue
            }

            if let currentTime = player?.currentTime().seconds, currentTime.isFinite {
                currentTimeSeconds = max(0, min(currentTime, durationSeconds))
            }
            isPlaying = player?.rate != 0
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.playImmediately(atRate: playbackRate)
            isPlaying = true
        }
    }

    private func seek(to seconds: Double) {
        let targetSeconds = max(0, min(seconds, durationSeconds))
        let target = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        currentTimeSeconds = targetSeconds
        player?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func seekToAbsolute(_ seconds: Double) {
        let targetSeconds = max(0, min(seconds, durationSeconds))
        let target = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        currentTimeSeconds = targetSeconds
        player?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func stepFrame(direction: Int) {
        player?.pause()
        isPlaying = false
        let frameStep = 1 / max(Double(sourceFrameRate), 1)
        seek(to: currentTimeSeconds + (Double(direction) * frameStep))
    }

    private func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        applyPlaybackTrimLimits()
        if isPlaying {
            player?.rate = rate
        }
    }

    private func applyStoredTrimIfNeeded() {
        activeTrimStartSeconds = clampedTrimStart(video.trimStartSeconds ?? 0)
        activeTrimEndSeconds = clampedTrimEnd(video.trimEndSeconds ?? sourceDurationSeconds)
        draftTrimStartSeconds = activeTrimStartSeconds
        draftTrimEndSeconds = activeTrimEndSeconds
        durationSeconds = hasActiveTrim ? max(playbackEndSeconds - playbackStartSeconds, 0.1) : sourceDurationSeconds
        currentTimeSeconds = 0
    }

    private func toggleInlineTrimControls() {
        if isShowingInlineTrimControls {
            isShowingInlineTrimControls = false
            reloadPlayerForCurrentTrim()
        } else {
            draftTrimStartSeconds = playbackStartSeconds
            draftTrimEndSeconds = playbackEndSeconds
            isShowingInlineTrimControls = true
            reloadPlayerForSource()
            seekToAbsolute(draftTrimStartSeconds)
        }
    }

    private func applyTrim(startTime: Double, endTime: Double) {
        let startTime = clampedTrimStart(startTime)
        let endTime = clampedTrimEnd(endTime, minimumStart: startTime)
        video.trimStartSeconds = startTime
        video.trimEndSeconds = endTime
        activeTrimStartSeconds = startTime
        activeTrimEndSeconds = endTime
        draftTrimStartSeconds = startTime
        draftTrimEndSeconds = endTime
        isShowingInlineTrimControls = false
        reloadPlayerForCurrentTrim()
        seek(to: 0)
    }

    private func revertTrim() {
        video.trimStartSeconds = nil
        video.trimEndSeconds = nil
        activeTrimStartSeconds = 0
        activeTrimEndSeconds = durationSeconds
        draftTrimStartSeconds = 0
        draftTrimEndSeconds = sourceDurationSeconds
        isShowingInlineTrimControls = false
        removeTrimEndBoundaryObserver()
        reloadPlayerForCurrentTrim()
        seek(to: 0)
        saveStatus = VideoSaveStatus(title: "Trim Reverted", message: "The full original video is available again.")
        isShowingSaveStatus = true
    }

    private func clampedTrimStart(_ seconds: Double) -> Double {
        max(0, min(seconds, max(sourceDurationSeconds - 0.2, 0)))
    }

    private func clampedTrimEnd(_ seconds: Double) -> Double {
        clampedTrimEnd(seconds, minimumStart: activeTrimStartSeconds)
    }

    private func clampedTrimEnd(_ seconds: Double, minimumStart: Double) -> Double {
        let minimumEnd = min(sourceDurationSeconds, minimumStart + 0.2)
        return max(minimumEnd, min(seconds, sourceDurationSeconds))
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let totalSeconds = max(Int(seconds), 0)
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }

    private func applyPlaybackTrimLimits() {
        guard let currentItem = player?.currentItem else { return }

        if hasActiveTrim, !isShowingInlineTrimControls {
            currentItem.forwardPlaybackEndTime = CMTime(seconds: durationSeconds, preferredTimescale: 600)

            if let currentSeconds = player?.currentTime().seconds,
               currentSeconds.isFinite,
               currentSeconds > durationSeconds {
                player?.pause()
                seek(to: durationSeconds)
            }
        } else {
            currentItem.forwardPlaybackEndTime = .invalid
        }
    }

    private func reloadPlayerForSource() {
        guard let url = video.fileURL else { return }
        removeTrimEndBoundaryObserver()
        removePlaybackProgressObserver()
        let item = AVPlayerItem(url: url)
        player?.replaceCurrentItem(with: item)
        durationSeconds = sourceDurationSeconds
        currentTimeSeconds = 0
        configurePlaybackProgressObserver()
        settlePlaybackAtBeginning()
    }

    private func reloadPlayerForCurrentTrim() {
        guard let url = video.fileURL else { return }
        removeTrimEndBoundaryObserver()
        removePlaybackProgressObserver()

        let item: AVPlayerItem
        if hasActiveTrim,
           let trimmedItem = Self.makeTrimmedPlaybackItem(
            sourceURL: url,
            startSeconds: playbackStartSeconds,
            endSeconds: playbackEndSeconds
           ) {
            item = trimmedItem
            durationSeconds = max(playbackEndSeconds - playbackStartSeconds, 0.1)
        } else {
            item = AVPlayerItem(url: url)
            durationSeconds = sourceDurationSeconds
        }

        player?.replaceCurrentItem(with: item)
        currentTimeSeconds = 0
        applyPlaybackTrimLimits()
        configureTrimEndBoundaryObserver()
        configurePlaybackProgressObserver()
        settlePlaybackAtBeginning()
    }

    private func settlePlaybackAtBeginning() {
        seek(to: 0)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            seek(to: 0)
        }
    }

    private static func makeTrimmedPlaybackItem(sourceURL: URL, startSeconds: Double, endSeconds: Double) -> AVPlayerItem? {
        let asset = AVURLAsset(url: sourceURL)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else { return nil }

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            return nil
        }

        let sourceRange = CMTimeRange(
            start: CMTime(seconds: startSeconds, preferredTimescale: 600),
            end: CMTime(seconds: endSeconds, preferredTimescale: 600)
        )

        do {
            try compositionVideoTrack.insertTimeRange(sourceRange, of: videoTrack, at: .zero)
            compositionVideoTrack.preferredTransform = videoTrack.preferredTransform

            if let audioTrack = asset.tracks(withMediaType: .audio).first,
               let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                try? compositionAudioTrack.insertTimeRange(sourceRange, of: audioTrack, at: .zero)
            }
        } catch {
            return nil
        }

        return AVPlayerItem(asset: composition)
    }

    private func configureTrimEndBoundaryObserver() {
        removeTrimEndBoundaryObserver()
        guard hasActiveTrim,
              let player,
              durationSeconds > 0 else {
            return
        }

        let endTime = CMTime(seconds: durationSeconds, preferredTimescale: 600)
        trimEndBoundaryObserver = player.addBoundaryTimeObserver(forTimes: [NSValue(time: endTime)], queue: .main) {
            player.pause()
            seek(to: durationSeconds)
        }
    }

    private func removeTrimEndBoundaryObserver() {
        if let trimEndBoundaryObserver {
            player?.removeTimeObserver(trimEndBoundaryObserver)
            self.trimEndBoundaryObserver = nil
        }
    }

    private func configurePlaybackProgressObserver() {
        removePlaybackProgressObserver()
        guard let player else { return }

        let interval = CMTime(value: 1, timescale: 30)
        playbackProgressObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard !isScrubbing, let seconds = time.seconds.isFinite ? Optional(time.seconds) : nil else {
                return
            }

            if isShowingInlineTrimControls {
                currentTimeSeconds = max(0, min(seconds, durationSeconds))
                return
            }

            guard hasActiveTrim else {
                currentTimeSeconds = max(0, min(seconds, durationSeconds))
                return
            }

            if seconds >= durationSeconds - 0.025 {
                player.pause()
                seek(to: durationSeconds)
            } else {
                currentTimeSeconds = seconds
            }
        }
    }

    private func removePlaybackProgressObserver() {
        if let playbackProgressObserver {
            player?.removeTimeObserver(playbackProgressObserver)
            self.playbackProgressObserver = nil
        }
    }

    private func saveVideoToPhotos(_ url: URL) {
        isSavingToPhotos = true
        Task {
            do {
                try await PhotoLibraryVideoSaver.saveVideoToCameraRoll(url: url)
                saveStatus = .success
            } catch {
                saveStatus = .failure(error.localizedDescription)
            }
            isSavingToPhotos = false
            isShowingSaveStatus = true
        }
    }
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

@MainActor
final class CoachAnalysisRecorder {
    private(set) var isRecording = false

    private let recorder = RPScreenRecorder.shared()
    private var outputURL: URL?

    func start() async throws {
        guard !isRecording else { return }

        if let issue = CoachAnalysisRecordingReadiness.blockingIssue {
            throw CoachAnalysisRecordingError.unavailable(issue)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            recorder.startRecording(withMicrophoneEnabled: true) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        isRecording = true
    }

    func stop() async throws -> URL {
        guard isRecording else {
            throw CoachAnalysisRecordingError.unavailable("No coach analysis recording is currently active.")
        }

        let destination = try VideoFileStore.makeDestinationURL(fileExtension: "mov")
        outputURL = destination

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                recorder.stopRecording(withOutput: destination) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }

            isRecording = false
            return destination
        } catch {
            isRecording = false
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}

enum CoachAnalysisRecordingReadiness {
    static var blockingIssue: String? {
        if missingInfoPlistValue(for: "NSMicrophoneUsageDescription") {
            return "Microphone permission is not configured. In Xcode, select the GOLF COACH app target, open Info, and add Privacy - Microphone Usage Description."
        }

        if !RPScreenRecorder.shared().isAvailable {
            return "Screen recording is not available right now. Stop AirPlay, screen mirroring, or any other active screen recording, then try again."
        }

        return nil
    }

    private static func missingInfoPlistValue(for key: String) -> Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return true
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum CoachAnalysisRecordingError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return message
        }
    }
}

struct ControlledVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    let showsPlaybackControls: Bool

    func makeUIViewController(context: Context) -> ZoomableAVPlayerViewController {
        let controller = ZoomableAVPlayerViewController()
        controller.update(player: player, showsPlaybackControls: showsPlaybackControls)
        return controller
    }

    func updateUIViewController(_ controller: ZoomableAVPlayerViewController, context: Context) {
        controller.update(player: player, showsPlaybackControls: showsPlaybackControls)
    }
}

final class ZoomableAVPlayerViewController: UIViewController, UIGestureRecognizerDelegate {
    private let playerViewController = AVPlayerViewController()
    private let minimumScale: CGFloat = 1
    private let maximumScale: CGFloat = 5
    private var currentScale: CGFloat = 1
    private var pinchStartScale: CGFloat = 1
    private var currentTranslation = CGPoint.zero
    private var panStartTranslation = CGPoint.zero

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
        view.clipsToBounds = true

        addChild(playerViewController)
        playerViewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(playerViewController.view)

        NSLayoutConstraint.activate([
            playerViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            playerViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        playerViewController.didMove(toParent: self)
        playerViewController.videoGravity = .resizeAspect
        configureGestures()
    }

    func update(player: AVPlayer, showsPlaybackControls: Bool) {
        playerViewController.player = player
        playerViewController.showsPlaybackControls = showsPlaybackControls
        playerViewController.view.isUserInteractionEnabled = showsPlaybackControls
    }

    private func configureGestures() {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        view.addGestureRecognizer(pinch)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.delegate = self
        view.addGestureRecognizer(pan)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(resetZoom))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        view.addGestureRecognizer(doubleTap)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            pinchStartScale = currentScale
        case .changed:
            currentScale = min(max(pinchStartScale * gesture.scale, minimumScale), maximumScale)
            clampTranslation()
            applyTransform()
        case .ended, .cancelled, .failed:
            if currentScale <= minimumScale {
                resetZoom()
            }
        default:
            break
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard currentScale > minimumScale else { return }

        switch gesture.state {
        case .began:
            panStartTranslation = currentTranslation
        case .changed:
            let translation = gesture.translation(in: view)
            currentTranslation = CGPoint(
                x: panStartTranslation.x + translation.x,
                y: panStartTranslation.y + translation.y
            )
            clampTranslation()
            applyTransform()
        default:
            break
        }
    }

    @objc private func resetZoom() {
        currentScale = minimumScale
        currentTranslation = .zero

        UIView.animate(withDuration: 0.2) {
            self.applyTransform()
        }
    }

    private func clampTranslation() {
        guard currentScale > minimumScale else {
            currentTranslation = .zero
            return
        }

        let horizontalLimit = (view.bounds.width * (currentScale - 1)) / 2
        let verticalLimit = (view.bounds.height * (currentScale - 1)) / 2
        currentTranslation.x = min(max(currentTranslation.x, -horizontalLimit), horizontalLimit)
        currentTranslation.y = min(max(currentTranslation.y, -verticalLimit), verticalLimit)
    }

    private func applyTransform() {
        let translation = CGAffineTransform(translationX: currentTranslation.x, y: currentTranslation.y)
        let scale = CGAffineTransform(scaleX: currentScale, y: currentScale)
        playerViewController.view.transform = translation.concatenating(scale)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer is UIPanGestureRecognizer {
            return currentScale > minimumScale
        }

        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

struct VideoReviewControls: View {
    @Binding var currentTime: Double
    let duration: Double
    let playbackRate: Float
    let frameRate: Float
    var showsDetailedControls = true
    var showsTrimControl = true
    let onScrubBegan: () -> Void
    let onScrubChanged: (Double) -> Void
    let onScrubEnded: (Double) -> Void
    let onRateSelected: (Float) -> Void
    let onStepFrameBackward: () -> Void
    let onStepFrameForward: () -> Void
    let onTrim: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(timeString(currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { currentTime },
                        set: { value in
                            currentTime = value
                            onScrubChanged(value)
                        }
                    ),
                    in: 0...max(duration, 0.1),
                    onEditingChanged: { editing in
                        if editing {
                            onScrubBegan()
                        } else {
                            onScrubEnded(currentTime)
                        }
                    }
                )
                Text(timeString(duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if showsDetailedControls {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Frame Review")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Frame \(frameNumber) | \(Int(frameRate.rounded())) fps")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Button(action: onStepFrameBackward) {
                            Label("Back 1 Frame", systemImage: "chevron.left.2")
                        }
                        .buttonStyle(.bordered)

                        Button(action: onStepFrameForward) {
                            Label("Forward 1 Frame", systemImage: "chevron.right.2")
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                    }
                    .font(.caption.weight(.semibold))
                }

                HStack(spacing: 8) {
                    ForEach([0.1, 0.25, 0.5, 1.0], id: \.self) { rate in
                        Button {
                            onRateSelected(Float(rate))
                        } label: {
                            Text(rate == 1.0 ? "1x" : "\(rate, specifier: "%.2gx")")
                                .font(.caption.weight(.semibold))
                                .frame(minWidth: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(playbackRate == Float(rate) ? .blue : .secondary)
                    }

                    if showsTrimControl {
                        Spacer()

                        Button(action: onTrim) {
                            Label("Trim", systemImage: "scissors")
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let totalSeconds = max(Int(seconds), 0)
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }

    private var frameStep: Double {
        1 / max(Double(frameRate), 1)
    }

    private var frameNumber: Int {
        max(Int((currentTime / frameStep).rounded()), 0)
    }
}

struct InlineTrimControls: View {
    @Binding var startTime: Double
    @Binding var endTime: Double
    let duration: Double
    let onHandleMoved: (Double) -> Void
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Trim Range", systemImage: "scissors")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(timeString(startTime)) - \(timeString(endTime))")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
            }

            TrimRangeSelector(
                startTime: $startTime,
                endTime: $endTime,
                duration: max(duration, 0.1),
                onHandleMoved: onHandleMoved
            )
            .frame(height: 58)

            HStack(spacing: 10) {
                Button(action: onApply) {
                    Label("Trim Video", systemImage: "scissors")
                }
                .buttonStyle(.borderedProminent)
                .disabled(endTime <= startTime)

                Spacer()
            }
            .font(.caption.weight(.semibold))
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let totalSeconds = max(Int(seconds), 0)
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }
}

struct TrimVideoView: View {
    @Environment(\.dismiss) private var dismiss
    let sourceURL: URL
    let duration: Double
    let initialStartTime: Double
    let initialEndTime: Double
    let onApply: (Double, Double) -> Void

    @State private var startTime = 0.0
    @State private var endTime: Double
    @State private var previewPlayer: AVPlayer
    @State private var previewTask: Task<Void, Never>?
    @State private var errorMessage: String?

    init(
        sourceURL: URL,
        duration: Double,
        initialStartTime: Double,
        initialEndTime: Double,
        onApply: @escaping (Double, Double) -> Void
    ) {
        self.sourceURL = sourceURL
        self.duration = duration
        self.initialStartTime = initialStartTime
        self.initialEndTime = initialEndTime
        self.onApply = onApply
        _startTime = State(initialValue: max(0, min(initialStartTime, max(duration - 0.2, 0))))
        _endTime = State(initialValue: max(0.2, min(initialEndTime, max(duration, 0.1))))
        _previewPlayer = State(initialValue: AVPlayer(url: sourceURL))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Preview") {
                    VideoPlayer(player: previewPlayer)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    TrimRangeSelector(
                        startTime: $startTime,
                        endTime: $endTime,
                        duration: max(duration, 0.1),
                        onHandleMoved: { time in
                            seekPreview(to: time)
                        }
                    )
                    .frame(height: 54)
                    .padding(.vertical, 8)

                    HStack {
                        LabeledContent("Start", value: timeString(startTime))
                        Spacer()
                        LabeledContent("End", value: timeString(endTime))
                    }
                    .font(.caption)

                    LabeledContent("Selected Length", value: timeString(max(endTime - startTime, 0)))

                    HStack {
                        Button {
                            seekPreview(to: startTime)
                        } label: {
                            Label("Show Start", systemImage: "backward.end")
                        }

                        Spacer()

                        Button {
                            playTrimPreview()
                        } label: {
                            Label("Preview Trim", systemImage: "play")
                        }
                    }
                    .font(.caption.weight(.semibold))

                    Button {
                        resetToFullVideo()
                    } label: {
                        Label("Reset Full Video", systemImage: "arrow.counterclockwise")
                    }
                    .font(.caption.weight(.semibold))
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Trim Video")
            .onAppear {
                seekPreview(to: startTime)
            }
            .onDisappear {
                previewTask?.cancel()
                previewPlayer.pause()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        applyTrim()
                    } label: {
                        Text("Apply")
                    }
                    .disabled(endTime <= startTime)
                }
            }
        }
    }

    private func applyTrim() {
        errorMessage = nil
        guard endTime > startTime else {
            errorMessage = "Move the trim handles so the end is after the start."
            return
        }
        onApply(startTime, endTime)
        dismiss()
    }

    private func seekPreview(to seconds: Double) {
        previewTask?.cancel()
        previewPlayer.pause()
        previewPlayer.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func playTrimPreview() {
        previewTask?.cancel()
        seekPreview(to: startTime)
        previewPlayer.play()
        let length = max(endTime - startTime, 0.1)
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(Int(length * 1000)))
            await MainActor.run {
                previewPlayer.pause()
                seekPreview(to: endTime)
            }
        }
    }

    private func resetToFullVideo() {
        startTime = 0
        endTime = max(duration, 0.1)
        seekPreview(to: startTime)
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let totalSeconds = max(Int(seconds), 0)
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }
}

struct TrimRangeSelector: View {
    @Binding var startTime: Double
    @Binding var endTime: Double
    let duration: Double
    let onHandleMoved: (Double) -> Void
    private let minimumSelectionLength = 0.2

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let startX = xPosition(for: startTime, width: width)
            let endX = xPosition(for: endTime, width: width)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.tertiarySystemFill))
                    .frame(height: 12)
                    .position(x: width / 2, y: proxy.size.height / 2)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.blue.opacity(0.24))
                    .frame(width: max(endX - startX, 1), height: 42)
                    .position(x: startX + ((endX - startX) / 2), y: proxy.size.height / 2)

                VStack(spacing: 3) {
                    Text("Start")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.blue)
                    trimHandle(systemImage: "chevron.left")
                }
                    .position(x: startX, y: proxy.size.height / 2)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let proposed = time(for: value.location.x, width: width)
                                startTime = min(max(proposed, 0), endTime - minimumSelectionLength)
                                onHandleMoved(startTime)
                            }
                    )

                VStack(spacing: 3) {
                    Text("End")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.blue)
                    trimHandle(systemImage: "chevron.right")
                }
                    .position(x: endX, y: proxy.size.height / 2)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let proposed = time(for: value.location.x, width: width)
                                endTime = max(min(proposed, duration), startTime + minimumSelectionLength)
                                onHandleMoved(endTime)
                            }
                    )
            }
        }
        .accessibilityLabel("Trim range selector")
    }

    private func trimHandle(systemImage: String) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Color.blue)
            .frame(width: 26, height: 44)
            .overlay {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        }

    private func xPosition(for time: Double, width: Double) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(time / duration, 0), 1) * width
    }

    private func time(for xPosition: Double, width: Double) -> Double {
        guard width > 0 else { return 0 }
        return min(max(xPosition / width, 0), 1) * duration
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

enum VideoTrimExporter {
    static func trimVideo(sourceURL: URL, startSeconds: Double, endSeconds: Double) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let asset = AVURLAsset(url: sourceURL)
            guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
                continuation.resume(throwing: SwingAnalysisExportError.exportSetupFailed)
                return
            }

            let outputFileType = SwingAnalysisVideoExporter.preferredOutputFileType(from: exporter.supportedFileTypes)
            let outputURL = try? VideoFileStore.makeDestinationURL(fileExtension: outputFileType.fileExtension)
            guard let outputURL else {
                continuation.resume(throwing: SwingAnalysisExportError.exportSetupFailed)
                return
            }

            exporter.outputURL = outputURL
            exporter.outputFileType = outputFileType
            exporter.timeRange = CMTimeRange(
                start: CMTime(seconds: startSeconds, preferredTimescale: 600),
                end: CMTime(seconds: endSeconds, preferredTimescale: 600)
            )
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed:
                    continuation.resume(returning: outputURL)
                case .failed, .cancelled:
                    continuation.resume(throwing: SwingAnalysisExportError.exportFailed(exporter.error?.localizedDescription))
                default:
                    continuation.resume(throwing: SwingAnalysisExportError.exportFailed(nil))
                }
            }
        }
    }
}

enum SwingAnalysisVideoExporter {
    static func exportAnnotatedVideo(
        sourceURL: URL,
        strokes: [SwingAnalysisStroke],
        startSeconds: Double = 0,
        endSeconds: Double? = nil
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            do {
                let asset = AVURLAsset(url: sourceURL)
                guard let videoTrack = asset.tracks(withMediaType: .video).first else {
                    throw SwingAnalysisExportError.missingVideoTrack
                }
                let assetDuration = asset.duration.seconds.isFinite ? asset.duration.seconds : 0
                let startTime = max(0, min(startSeconds, max(assetDuration - 0.2, 0)))
                let endTime = max(startTime + 0.2, min(endSeconds ?? assetDuration, assetDuration))
                let sourceTimeRange = CMTimeRange(
                    start: CMTime(seconds: startTime, preferredTimescale: 600),
                    end: CMTime(seconds: endTime, preferredTimescale: 600)
                )

                let transformedSize = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
                let renderSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
                guard renderSize.width > 0, renderSize.height > 0 else {
                    throw SwingAnalysisExportError.invalidVideoSize
                }

                let composition = AVMutableComposition()
                guard let compositionTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else {
                    throw SwingAnalysisExportError.exportSetupFailed
                }

                try compositionTrack.insertTimeRange(
                    sourceTimeRange,
                    of: videoTrack,
                    at: .zero
                )

                if let audioTrack = asset.tracks(withMediaType: .audio).first,
                   let compositionAudioTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                   ) {
                    try? compositionAudioTrack.insertTimeRange(
                        sourceTimeRange,
                        of: audioTrack,
                        at: .zero
                    )
                }

                let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)
                layerInstruction.setTransform(videoTrack.preferredTransform, at: .zero)

                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
                instruction.layerInstructions = [layerInstruction]

                let videoComposition = AVMutableVideoComposition()
                videoComposition.renderSize = renderSize
                let sourceFrameRate = videoTrack.nominalFrameRate.isFinite ? videoTrack.nominalFrameRate : 30
                let outputFrameRate = max(Int(sourceFrameRate.rounded()), 30)
                videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(outputFrameRate))
                videoComposition.instructions = [instruction]

                let parentLayer = CALayer()
                let videoLayer = CALayer()
                let drawingLayer = makeDrawingLayer(strokes: strokes, renderSize: renderSize)

                parentLayer.frame = CGRect(origin: .zero, size: renderSize)
                videoLayer.frame = parentLayer.frame
                drawingLayer.frame = parentLayer.frame
                parentLayer.addSublayer(videoLayer)
                parentLayer.addSublayer(drawingLayer)

                videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
                    postProcessingAsVideoLayer: videoLayer,
                    in: parentLayer
                )

                guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
                    throw SwingAnalysisExportError.exportSetupFailed
                }

                let outputFileType = preferredOutputFileType(from: exporter.supportedFileTypes)
                let outputURL = FileManager.default.temporaryDirectory
                    .appending(path: "SwingAnalysis-\(UUID().uuidString).\(outputFileType.fileExtension)")

                exporter.outputURL = outputURL
                exporter.outputFileType = outputFileType
                exporter.videoComposition = videoComposition
                exporter.exportAsynchronously {
                    switch exporter.status {
                    case .completed:
                        continuation.resume(returning: outputURL)
                    case .failed, .cancelled:
                        continuation.resume(throwing: SwingAnalysisExportError.exportFailed(exporter.error?.localizedDescription))
                    default:
                        continuation.resume(throwing: SwingAnalysisExportError.exportFailed(nil))
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func makeDrawingLayer(strokes: [SwingAnalysisStroke], renderSize: CGSize) -> CALayer {
        let layer = CALayer()
        layer.frame = CGRect(origin: .zero, size: renderSize)
        layer.isGeometryFlipped = true

        for stroke in strokes where stroke.points.count > 1 {
            let path = makeCGPath(for: stroke, renderSize: renderSize)

            let shapeLayer = CAShapeLayer()
            shapeLayer.path = path
            shapeLayer.strokeColor = stroke.drawingColor.uiColor.cgColor
            shapeLayer.fillColor = UIColor.clear.cgColor
            shapeLayer.lineWidth = max(renderSize.width, renderSize.height) * 0.006
            shapeLayer.lineCap = .round
            shapeLayer.lineJoin = .round
            shapeLayer.shadowColor = UIColor.black.cgColor
            shapeLayer.shadowOpacity = 0.8
            shapeLayer.shadowRadius = 2
            shapeLayer.shadowOffset = .zero
            layer.addSublayer(shapeLayer)
        }

        return layer
    }

    private static func denormalizedPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }

    private static func makeCGPath(for stroke: SwingAnalysisStroke, renderSize: CGSize) -> CGPath {
        switch stroke.drawingTool {
        case .line:
            let path = CGMutablePath()
            path.move(to: denormalizedPoint(stroke.points[0], in: renderSize))
            path.addLine(to: denormalizedPoint(stroke.points.last ?? stroke.points[0], in: renderSize))
            return path
        case .circle:
            let start = denormalizedPoint(stroke.points[0], in: renderSize)
            let end = denormalizedPoint(stroke.points.last ?? stroke.points[0], in: renderSize)
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(start.x - end.x),
                height: abs(start.y - end.y)
            )
            return CGPath(ellipseIn: rect, transform: nil)
        case .freehand:
            let path = CGMutablePath()
            path.move(to: denormalizedPoint(stroke.points[0], in: renderSize))
            path.addLine(to: denormalizedPoint(stroke.points.last ?? stroke.points[0], in: renderSize))
            return path
        }
    }

    static func preferredOutputFileType(from supportedTypes: [AVFileType]) -> AVFileType {
        if supportedTypes.contains(.mp4) {
            return .mp4
        }

        if supportedTypes.contains(.mov) {
            return .mov
        }

        return supportedTypes.first ?? .mov
    }
}

enum SwingAnalysisExportError: LocalizedError {
    case missingVideoTrack
    case invalidVideoSize
    case exportSetupFailed
    case exportFailed(String?)

    var errorDescription: String? {
        switch self {
        case .missingVideoTrack:
            return "This file does not contain a video track."
        case .invalidVideoSize:
            return "The video size could not be read."
        case .exportSetupFailed:
            return "The annotated video export could not be prepared."
        case .exportFailed(let reason):
            if let reason, !reason.isEmpty {
                return "The annotated video export failed: \(reason)"
            }
            return "The annotated video export failed."
        }
    }
}

extension AVFileType {
    var fileExtension: String {
        switch self {
        case .mp4:
            return "mp4"
        case .mov:
            return "mov"
        case .m4v:
            return "m4v"
        default:
            return "mov"
        }
    }
}

struct CalendarEventEditor: UIViewControllerRepresentable {
    let student: Student
    let lesson: LessonAppointment
    private let eventStore = EKEventStore()

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let event = EKEvent(eventStore: eventStore)
        event.title = "\(lesson.title): \(student.name)"
        event.startDate = lesson.scheduledAt
        event.endDate = lesson.endDate
        event.location = lesson.location
        event.notes = lesson.notes
        event.calendar = eventStore.defaultCalendarForNewEvents

        if let offset = lesson.reminderLeadTime.notificationOffset {
            event.alarms = [EKAlarm(relativeOffset: -offset)]
        }

        let controller = EKEventEditViewController()
        controller.eventStore = eventStore
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            controller.dismiss(animated: true)
        }
    }
}

struct VideoCaptureView: UIViewControllerRepresentable {
    let onVideoCaptured: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.mediaTypes = [UTType.movie.identifier]
        picker.videoQuality = .typeHigh
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: VideoCaptureView

        init(parent: VideoCaptureView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = info[.mediaURL] as? URL {
                parent.onVideoCaptured(url)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct MailComposerView: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String
    let body: String
    let attachmentData: Data
    let attachmentMimeType: String
    let attachmentFileName: String
    let onFinish: (EmailStatus) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(recipients)
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        controller.addAttachmentData(
            attachmentData,
            mimeType: attachmentMimeType,
            fileName: attachmentFileName
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss, onFinish: onFinish)
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction
        let onFinish: (EmailStatus) -> Void

        init(dismiss: DismissAction, onFinish: @escaping (EmailStatus) -> Void) {
            self.dismiss = dismiss
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            onFinish(EmailStatus(result: result, error: error))
            dismiss()
        }
    }
}

struct MarketingMailComposerView: UIViewControllerRepresentable {
    let toRecipient: String
    let blindCopyRecipients: [String]
    let subject: String
    let body: String
    let onFinish: (MFMailComposeResult, Error?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([toRecipient])
        controller.setBccRecipients(blindCopyRecipients)
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss, onFinish: onFinish)
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction
        let onFinish: (MFMailComposeResult, Error?) -> Void

        init(dismiss: DismissAction, onFinish: @escaping (MFMailComposeResult, Error?) -> Void) {
            self.dismiss = dismiss
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            onFinish(result, error)
            dismiss()
        }
    }
}

struct LessonEmailComposerView: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String
    let body: String
    let imageAttachments: [Data]
    let onFinish: (String?) -> Void
    @Environment(\.dismiss) private var dismiss

    init(
        recipients: [String],
        subject: String,
        body: String,
        imageAttachments: [Data] = [],
        onFinish: @escaping (String?) -> Void
    ) {
        self.recipients = recipients
        self.subject = subject
        self.body = body
        self.imageAttachments = imageAttachments
        self.onFinish = onFinish
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(recipients)
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        for (index, data) in imageAttachments.enumerated() {
            controller.addAttachmentData(
                data,
                mimeType: "image/jpeg",
                fileName: "swing-screenshot-\(index + 1).jpg"
            )
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {
        uiViewController.setToRecipients(recipients)
        uiViewController.setSubject(subject)
        uiViewController.setMessageBody(body, isHTML: false)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss, onFinish: onFinish)
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction
        let onFinish: (String?) -> Void

        init(dismiss: DismissAction, onFinish: @escaping (String?) -> Void) {
            self.dismiss = dismiss
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            if let error {
                onFinish(String(localized: "Email failed to send: \(error.localizedDescription)"))
            } else {
                switch result {
                case .sent:
                    onFinish(String(localized: "Email sent."))
                case .saved:
                    onFinish(String(localized: "Email saved as draft."))
                case .failed:
                    onFinish(String(localized: "Email failed to send."))
                case .cancelled:
                    onFinish(nil)
                @unknown default:
                    onFinish(nil)
                }
            }
            dismiss()
        }
    }
}

struct MessageComposerView: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    let onFinish: (String?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.recipients = recipients
        controller.body = body
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {
        uiViewController.recipients = recipients
        uiViewController.body = body
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss, onFinish: onFinish)
    }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let dismiss: DismissAction
        let onFinish: (String?) -> Void

        init(dismiss: DismissAction, onFinish: @escaping (String?) -> Void) {
            self.dismiss = dismiss
            self.onFinish = onFinish
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            switch result {
            case .sent:
                onFinish("Text message sent.")
            case .failed:
                onFinish("Text message failed to send.")
            case .cancelled:
                onFinish(nil)
            @unknown default:
                onFinish(nil)
            }
            dismiss()
        }
    }
}

struct EmailStatus: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let systemImage: String
    let tint: Color

    static let mailUnavailable = EmailStatus(
        title: "Mail Unavailable",
        message: "The Simulator usually cannot send email because Mail is not configured. Use Share Excel File in the Simulator, or run the app on an iPhone with a Mail account to send directly.",
        systemImage: "envelope.badge",
        tint: .orange
    )

    init(title: String, message: String, systemImage: String, tint: Color) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.tint = tint
    }

    init(result: MFMailComposeResult, error: Error?) {
        if let error {
            title = "Email Failed"
            message = error.localizedDescription
            systemImage = "xmark.circle"
            tint = .red
            return
        }

        switch result {
        case .sent:
            title = "Email Sent"
            message = "Mail accepted the student export and queued it to send. Check Mail's Sent folder to confirm final delivery."
            systemImage = "checkmark.circle"
            tint = .green
        case .saved:
            title = "Draft Saved"
            message = "The email was saved as a draft and has not been sent yet."
            systemImage = "doc"
            tint = .orange
        case .cancelled:
            title = "Email Cancelled"
            message = "The export email was cancelled before sending."
            systemImage = "xmark.circle"
            tint = .secondary
        case .failed:
            title = "Email Failed"
            message = "Mail could not send the export. Check the account setup and try again."
            systemImage = "exclamationmark.triangle"
            tint = .red
        @unknown default:
            title = "Email Status Unknown"
            message = "Mail returned an unknown status. Check the Mail app for the message."
            systemImage = "questionmark.circle"
            tint = .secondary
        }
    }
}

struct GolfCoachBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let snapshot: GolfCoachBackupSnapshot

    init(snapshot: GolfCoachBackupSnapshot) {
        self.snapshot = snapshot
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        snapshot = try GolfCoachBackupSnapshot.decode(from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try snapshot.encodedData())
    }
}

struct GolfCoachBackupSnapshot: Codable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let createdAt: Date
    let students: [StudentBackupRecord]

    static var fileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "GolfCoachBackup-\(formatter.string(from: .now)).json"
    }

    init(students: [Student]) {
        formatVersion = Self.currentFormatVersion
        createdAt = .now
        self.students = students.map(StudentBackupRecord.init)
    }

    func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(from data: Data) throws -> GolfCoachBackupSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(GolfCoachBackupSnapshot.self, from: data)
        guard snapshot.formatVersion == currentFormatVersion else {
            throw BackupRestoreError.unsupportedVersion(snapshot.formatVersion)
        }
        return snapshot
    }
}

struct StudentBackupRecord: Codable {
    let studentIdentifier: String?
    let name: String
    let phoneNumber: String
    let email: String
    let birthday: Date?
    let referralPersonName: String?
    let age: String?
    let yearsOfExperience: String?
    let handicap: String?
    let golfGoal: String?
    let jobInfo: String?
    let createdAt: Date
    let photoData: Data?
    let packages: [LessonPackageBackupRecord]
    let lessons: [LessonAppointmentBackupRecord]
    let videos: [LessonVideoBackupRecord]
    let sessionNotes: [LessonSessionNoteBackupRecord]

    enum CodingKeys: String, CodingKey {
        case studentIdentifier
        case name
        case phoneNumber
        case email
        case birthday
        case referralPersonName
        case age
        case yearsOfExperience
        case handicap
        case golfGoal
        case jobInfo
        case createdAt
        case photoData
        case packages
        case lessons
        case videos
        case sessionNotes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        studentIdentifier = try container.decodeIfPresent(String.self, forKey: .studentIdentifier)
        name = try container.decode(String.self, forKey: .name)
        phoneNumber = try container.decode(String.self, forKey: .phoneNumber)
        email = try container.decode(String.self, forKey: .email)
        birthday = try container.decodeIfPresent(Date.self, forKey: .birthday)
        referralPersonName = try container.decodeIfPresent(String.self, forKey: .referralPersonName)
        age = try container.decodeIfPresent(String.self, forKey: .age)
        yearsOfExperience = try container.decodeIfPresent(String.self, forKey: .yearsOfExperience)
        handicap = try container.decodeIfPresent(String.self, forKey: .handicap)
        golfGoal = try container.decodeIfPresent(String.self, forKey: .golfGoal)
        jobInfo = try container.decodeIfPresent(String.self, forKey: .jobInfo)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        photoData = try container.decodeIfPresent(Data.self, forKey: .photoData)
        packages = try container.decode([LessonPackageBackupRecord].self, forKey: .packages)
        lessons = try container.decode([LessonAppointmentBackupRecord].self, forKey: .lessons)
        videos = try container.decodeIfPresent([LessonVideoBackupRecord].self, forKey: .videos) ?? []
        sessionNotes = try container.decode([LessonSessionNoteBackupRecord].self, forKey: .sessionNotes)
    }

    init(student: Student) {
        let storedStudentIdentifier = student.persistentModelID.storeIdentifier
        studentIdentifier = storedStudentIdentifier
        name = student.name
        phoneNumber = student.phoneNumber
        email = student.email
        birthday = student.birthday
        referralPersonName = student.referralPersonName
        age = student.age
        yearsOfExperience = student.yearsOfExperience
        handicap = student.handicap
        golfGoal = student.golfGoal
        jobInfo = student.jobInfo
        createdAt = student.createdAt
        photoData = student.photoData
        packages = student.packages.map(LessonPackageBackupRecord.init)
        lessons = student.lessons.map(LessonAppointmentBackupRecord.init)
        videos = LessonVideoDisplayStore.uniqueVideos(in: student.videos).map { video in
            LessonVideoBackupRecord(
                video: video,
                studentIdentifier: storedStudentIdentifier,
                lessonIdentifier: Self.lessonIdentifier(for: video, in: student.lessons)
            )
        }
        sessionNotes = student.sessionNotes.map(LessonSessionNoteBackupRecord.init)
    }

    func makeStudent() -> Student {
        Student(
            name: name,
            phoneNumber: phoneNumber,
            email: email,
            birthday: birthday,
            referralPersonName: referralPersonName,
            age: age,
            yearsOfExperience: yearsOfExperience,
            handicap: handicap,
            golfGoal: golfGoal,
            jobInfo: jobInfo,
            createdAt: createdAt,
            photoData: photoData,
            packages: packages.map { $0.makePackage() },
            lessons: lessons.map { $0.makeLesson() },
            videos: videos.map { $0.makeVideo() },
            sessionNotes: sessionNotes.map { $0.makeNote() }
        )
    }

    private static func lessonIdentifier(for video: LessonVideo, in lessons: [LessonAppointment]) -> String? {
        let lessonDate = video.lessonDate ?? video.recordedAt
        return lessons
            .first { Calendar.current.isDate($0.scheduledAt, inSameDayAs: lessonDate) }?
            .persistentModelID
            .storeIdentifier
    }
}

struct LessonPackageBackupRecord: Codable {
    let packageTypeRawValue: String
    let lessonsPurchased: Int
    let lessonsUsed: Int
    let totalPaid: Decimal
    let purchaseDate: Date
    let paymentMethodRawValue: String?
    let charges: [LessonChargeBackupRecord]?

    init(package: LessonPackage) {
        packageTypeRawValue = package.packageTypeRawValue
        lessonsPurchased = package.lessonsPurchased
        lessonsUsed = package.lessonsUsed
        totalPaid = package.totalPaid
        purchaseDate = package.purchaseDate
        paymentMethodRawValue = package.paymentMethodRawValue
        charges = package.charges.map(LessonChargeBackupRecord.init)
    }

    func makePackage() -> LessonPackage {
        LessonPackage(
            packageType: LessonPackageType(rawValue: packageTypeRawValue) ?? .custom,
            lessonsPurchased: lessonsPurchased,
            lessonsUsed: lessonsUsed,
            totalPaid: totalPaid,
            purchaseDate: purchaseDate,
            paymentMethod: paymentMethodRawValue.flatMap(PaymentMethod.init(rawValue:)),
            charges: charges?.map { $0.makeCharge() } ?? []
        )
    }
}

struct LessonChargeBackupRecord: Codable {
    let chargedAt: Date
    let durationMinutes: Int
    let participantCount: Int
    let amount: Decimal
    let notes: String

    init(charge: LessonCharge) {
        chargedAt = charge.chargedAt
        durationMinutes = charge.durationMinutes
        participantCount = charge.participantCount
        amount = charge.amount
        notes = charge.notes
    }

    func makeCharge() -> LessonCharge {
        LessonCharge(
            chargedAt: chargedAt,
            durationMinutes: durationMinutes,
            participantCount: participantCount,
            amount: amount,
            notes: notes
        )
    }
}

struct LessonAppointmentBackupRecord: Codable {
    let title: String
    let scheduledAt: Date
    let durationMinutes: Int
    let location: String
    let notes: String
    let reminderLeadTimeRawValue: String
    let isCompleted: Bool

    init(lesson: LessonAppointment) {
        title = lesson.title
        scheduledAt = lesson.scheduledAt
        durationMinutes = lesson.durationMinutes
        location = lesson.location
        notes = lesson.notes
        reminderLeadTimeRawValue = lesson.reminderLeadTimeRawValue
        isCompleted = lesson.isCompleted
    }

    func makeLesson() -> LessonAppointment {
        LessonAppointment(
            title: title,
            scheduledAt: scheduledAt,
            durationMinutes: durationMinutes,
            location: location,
            notes: notes,
            reminderLeadTime: ReminderLeadTime(rawValue: reminderLeadTimeRawValue) ?? .none,
            isCompleted: isCompleted
        )
    }
}

struct LessonVideoBackupRecord: Codable {
    let studentIdentifier: String?
    let lessonIdentifier: String?
    let title: String
    let recordedAt: Date
    let notes: String
    let originalLocalVideoPath: String?
    let lessonDate: Date?
    let durationSeconds: Double?
    let thumbnailReference: String?
    let focusNotes: String?
    let problemNotes: String?
    let comparisonNotes: String?
    let analysisDrawingData: String?
    let trimStartSeconds: Double?
    let trimEndSeconds: Double?

    init(video: LessonVideo, studentIdentifier: String?, lessonIdentifier: String?) {
        self.studentIdentifier = studentIdentifier
        self.lessonIdentifier = lessonIdentifier
        title = video.title
        recordedAt = video.recordedAt
        notes = video.notes
        originalLocalVideoPath = video.fileURLString
        lessonDate = video.lessonDate
        durationSeconds = Self.durationSeconds(for: video.fileURL)
        thumbnailReference = nil
        focusNotes = video.focusNotes
        problemNotes = video.problemNotes
        comparisonNotes = video.comparisonNotes
        analysisDrawingData = video.analysisDrawingData
        trimStartSeconds = video.trimStartSeconds
        trimEndSeconds = video.trimEndSeconds
    }

    func makeVideo() -> LessonVideo {
        LessonVideo(
            title: title,
            recordedAt: recordedAt,
            notes: notes,
            fileURLString: originalLocalVideoPath,
            lessonDate: lessonDate,
            focusNotes: focusNotes,
            problemNotes: problemNotes,
            comparisonNotes: comparisonNotes,
            analysisDrawingData: analysisDrawingData,
            trimStartSeconds: trimStartSeconds,
            trimEndSeconds: trimEndSeconds
        )
    }

    private static func durationSeconds(for url: URL?) -> Double? {
        guard let url else { return nil }
        let duration = AVURLAsset(url: url).duration.seconds
        return duration.isFinite && duration > 0 ? duration : nil
    }
}

struct LessonSessionNoteBackupRecord: Codable {
    let sessionDate: Date
    let focus: String
    let problems: String
    let improvements: String
    let generalNotes: String
    let lessonFocus: String?
    let coachNotes: String?
    let homework: String?
    let drills: String?
    let nextLessonGoal: String?
    let privateCoachJournal: String?
    let imageAttachments: [LessonNoteImageAttachmentBackupRecord]?
    let assignedDrills: [DrillBackupRecord]?

    init(note: LessonSessionNote) {
        sessionDate = note.sessionDate
        focus = note.focus
        problems = note.problems
        improvements = note.improvements
        generalNotes = note.generalNotes
        lessonFocus = note.lessonFocus
        coachNotes = note.coachNotes
        homework = note.homework
        drills = note.drills
        nextLessonGoal = note.nextLessonGoal
        privateCoachJournal = note.privateCoachJournal
        imageAttachments = note.imageAttachments.map {
            LessonNoteImageAttachmentBackupRecord(
                imageData: $0.imageData,
                createdAt: $0.createdAt,
                caption: $0.caption
            )
        }
        assignedDrills = note.assignedDrills.map {
            DrillBackupRecord(
                title: $0.title,
                category: $0.category,
                purpose: $0.purpose,
                instructions: $0.instructions,
                recommendedReps: $0.recommendedReps,
                coachTips: $0.coachTips,
                createdAt: $0.createdAt,
                demoVideoFileName: $0.demoVideoFileName,
                imageData: $0.imageData
            )
        }
    }

    func makeNote() -> LessonSessionNote {
        LessonSessionNote(
            sessionDate: sessionDate,
            focus: focus,
            problems: problems,
            improvements: improvements,
            generalNotes: generalNotes,
            lessonFocus: lessonFocus ?? "",
            coachNotes: coachNotes ?? "",
            homework: homework ?? "",
            drills: drills ?? "",
            nextLessonGoal: nextLessonGoal ?? "",
            privateCoachJournal: privateCoachJournal ?? "",
            imageAttachments: imageAttachments?.map { $0.makeAttachment() } ?? [],
            assignedDrills: assignedDrills?.map { $0.makeDrill() } ?? []
        )
    }
}

struct LessonNoteImageAttachmentBackupRecord: Codable {
    let imageData: Data
    let createdAt: Date
    let caption: String

    init(attachment: LessonNoteImageAttachment) {
        imageData = attachment.imageData
        createdAt = attachment.createdAt
        caption = attachment.caption
    }

    init(imageData: Data, createdAt: Date, caption: String) {
        self.imageData = imageData
        self.createdAt = createdAt
        self.caption = caption
    }

    func makeAttachment() -> LessonNoteImageAttachment {
        LessonNoteImageAttachment(
            imageData: imageData,
            createdAt: createdAt,
            caption: caption
        )
    }
}

struct DrillBackupRecord: Codable {
    let title: String
    let category: String
    let purpose: String
    let instructions: String
    let recommendedReps: String
    let coachTips: String
    let createdAt: Date
    let demoVideoFileName: String?
    let imageData: Data?

    func makeDrill() -> Drill {
        Drill(
            title: title,
            category: category,
            purpose: purpose,
            instructions: instructions,
            recommendedReps: recommendedReps,
            coachTips: coachTips,
            createdAt: createdAt,
            demoVideoFileName: demoVideoFileName,
            imageData: imageData
        )
    }
}

enum BackupRestoreError: LocalizedError {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "This backup uses unsupported format version \(version)."
        }
    }
}

enum AutomaticBackupStore {
    private static let interval: TimeInterval = 3 * 60 * 60
    private static let maximumBackupCount = 30
    private static let lastBackupDateKey = "GolfCoachLastAutomaticBackupDate"
    private static let filePrefix = "GolfCoachAutomaticBackup-"

    static var hasBackup: Bool {
        (try? latestBackupURL()) != nil
    }

    static func isBackupDue(now: Date = .now) -> Bool {
        guard let lastBackupDate = UserDefaults.standard.object(forKey: lastBackupDateKey) as? Date else {
            return true
        }
        return now.timeIntervalSince(lastBackupDate) >= interval
    }

    static func save(snapshot: GolfCoachBackupSnapshot) throws {
        let directory = try backupsDirectory()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let url = directory.appending(path: "\(filePrefix)\(formatter.string(from: snapshot.createdAt)).json")
        try snapshot.encodedData().write(to: url, options: .atomic)
        UserDefaults.standard.set(snapshot.createdAt, forKey: lastBackupDateKey)
        try pruneOldBackups(in: directory)
    }

    static func latestSnapshot() throws -> GolfCoachBackupSnapshot? {
        guard let url = try latestBackupURL() else { return nil }
        return try GolfCoachBackupSnapshot.decode(from: Data(contentsOf: url))
    }

    private static func backupsDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport.appending(path: "AutomaticBackups", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func latestBackupURL() throws -> URL? {
        let directory = try backupsDirectory()
        return try backupURLs(in: directory).first
    }

    private static func pruneOldBackups(in directory: URL) throws {
        let excessBackups = try backupURLs(in: directory).dropFirst(maximumBackupCount)
        for url in excessBackups {
            try FileManager.default.removeItem(at: url)
        }
    }

    private static func backupURLs(in directory: URL) throws -> [URL] {
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey]
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: .skipsHiddenFiles
        )
        return try urls
            .filter { $0.lastPathComponent.hasPrefix(filePrefix) && $0.pathExtension == "json" }
            .sorted {
                let leftDate = try $0.resourceValues(forKeys: resourceKeys).contentModificationDate ?? .distantPast
                let rightDate = try $1.resourceValues(forKeys: resourceKeys).contentModificationDate ?? .distantPast
                return leftDate > rightDate
            }
    }
}

enum StudentExporter {
    static var fileName: String {
        "GolfCoachStudents.csv"
    }

    static func makeExportFile(students: [Student]) throws -> (url: URL, data: Data) {
        let data = makeCSV(students: students)
        let directory = FileManager.default.temporaryDirectory
        let url = directory.appending(path: fileName)
        try data.write(to: url, options: .atomic)
        return (url, data)
    }

    private static func makeCSV(students: [Student]) -> Data {
        let header = [
            "Student Name",
            "Phone Number",
            "Email",
            "Birthday",
            "Referral Person Name",
            "Years of Experience",
            "Handicap",
            "Golf Goal",
            "Occupation",
            "Lessons Paid For",
            "Sessions Charged",
            "Package Lesson Slots Remaining (Reference)",
            "Total Money Paid",
            "Amount Deducted",
            "Remaining Value",
            "Active Package",
            "Payment Methods",
            "Upcoming Lessons",
            "Saved Videos"
        ]

        let rows = students.map { student in
            let lessonsPaidFor = student.packages.reduce(0) { $0 + $1.lessonsPurchased }
            let lessonsUsed = student.packages.reduce(0) { $0 + $1.lessonsUsed }
            let amountDeducted = student.packages.reduce(Decimal.zero) { $0 + $1.amountDeducted }
            let remainingValue = student.packages.reduce(Decimal.zero) { $0 + $1.remainingValue }
            let upcomingLessons = student.lessons.filter { !$0.isCompleted && $0.scheduledAt >= .now }.count
            let paymentMethods = student.packages
                .sorted { $0.purchaseDate > $1.purchaseDate }
                .compactMap(\.paymentMethod?.rawValue)
                .joined(separator: "; ")

            return [
                student.name,
                student.phoneNumber,
                student.email,
                student.birthday.map(dateString) ?? "",
                student.referralPersonName ?? "",
                student.yearsOfExperience ?? "",
                student.handicap ?? "",
                student.golfGoal ?? "",
                student.jobInfo ?? "",
                "\(lessonsPaidFor)",
                "\(lessonsUsed)",
                "\(student.remainingLessons)",
                decimalString(student.totalPaid),
                decimalString(amountDeducted),
                decimalString(remainingValue),
                student.activePackage?.packageType.rawValue ?? "",
                paymentMethods,
                "\(upcomingLessons)",
                "\(student.videos.count)"
            ]
        }

        let csvLines = ([header] + rows).map { row in
            row.map(escape).joined(separator: ",")
        }

        let csv = csvLines.joined(separator: "\n")
        return Data(csv.utf8)
    }

    nonisolated private static func escape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\n") || escaped.contains("\"") {
            return "\"\(escaped)\""
        }
        return escaped
    }

    nonisolated private static func decimalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    nonisolated private static func dateString(_ value: Date) -> String {
        value.formatted(.iso8601.year().month().day())
    }
}

enum PhotoLibraryVideoSaver {
    static func saveVideoToCameraRoll(url: URL) async throws {
        guard !missingInfoPlistValue(for: "NSPhotoLibraryAddUsageDescription") else {
            throw PhotoLibrarySaveError.missingAddPermissionDescription
        }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PhotoLibrarySaveError.permissionDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PhotoLibrarySaveError.saveFailed)
                }
            }
        }
    }

    private static func missingInfoPlistValue(for key: String) -> Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return true
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum PhotoLibrarySaveError: LocalizedError {
    case missingAddPermissionDescription
    case permissionDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .missingAddPermissionDescription:
            return "Photo library save permission is not configured. In Xcode, add NSPhotoLibraryAddUsageDescription to the GOLF COACH app target."
        case .permissionDenied:
            return "Photos permission was denied. Allow Golf Coach to add photos in Settings, then try again."
        case .saveFailed:
            return "Photos could not save this video."
        }
    }
}

struct VideoSaveStatus: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    static let success = VideoSaveStatus(
        title: "Saved to Photos",
        message: "The swing video was saved to your Camera Roll."
    )

    static func failure(_ message: String) -> VideoSaveStatus {
        VideoSaveStatus(title: "Save Failed", message: message)
    }
}

enum VideoFileStore {
    nonisolated static func persistedFileName(for url: URL) -> String {
        url.lastPathComponent
    }

    static func logVideoImport(url: URL, source: String) async {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration).seconds
            let fileType = url.pathExtension.isEmpty ? "unknown" : url.pathExtension
            print("DEBUG LessonVideo import source=\(source) type=\(fileType) fileURL=\(url.path) duration=\(duration)")
        } catch {
            print("DEBUG LessonVideo import metadata failed source=\(source) type=\(url.pathExtension) fileURL=\(url.path) error=\(error.localizedDescription)")
        }
    }

    static func importFailureMessage(_ error: Error) -> String {
        "The video could not be imported: \(error.localizedDescription). If this is an HEVC, HDR, or Cinematic video in Simulator, try an H.264 MP4 or test on a real iPhone."
    }

    nonisolated static func copyVideo(from url: URL) throws -> URL {
        let destination = try makeDestinationURL(fileExtension: url.pathExtension.isEmpty ? "mov" : url.pathExtension)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    static func deleteStoredVideoFile(for video: LessonVideo) {
        guard let url = video.fileURL,
              isAppStoredVideo(url) else {
            return
        }

        try? FileManager.default.removeItem(at: url)
    }

    static func deleteStoredVideoFile(fileName: String?) {
        guard let fileName,
              let url = storedVideoURL(fileName: fileName),
              isAppStoredVideo(url) else {
            return
        }

        try? FileManager.default.removeItem(at: url)
    }

    nonisolated static func storedVideoURL(fileName: String) -> URL? {
        guard let documents = try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return nil
        }

        let url = documents
            .appending(path: "GolfCoachVideos", directoryHint: .isDirectory)
            .appending(path: fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    nonisolated static func makeDestinationURL(fileExtension: String) throws -> URL {
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = documents.appending(path: "GolfCoachVideos", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "\(UUID().uuidString).\(fileExtension)")
    }

    private static func isAppStoredVideo(_ url: URL) -> Bool {
        guard let documents = try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return false
        }

        let videoDirectory = documents
            .appending(path: "GolfCoachVideos", directoryHint: .isDirectory)
            .standardizedFileURL
        return url.standardizedFileURL.path.hasPrefix(videoDirectory.path)
    }
}

enum VideoCaptureReadiness {
    static var blockingIssue: String? {
        if missingInfoPlistValue(for: "NSCameraUsageDescription") {
            return "Camera permission is not configured. In Xcode, select the GOLF COACH app target, open Info, and add Privacy - Camera Usage Description."
        }

        if missingInfoPlistValue(for: "NSMicrophoneUsageDescription") {
            return "Microphone permission is not configured. In Xcode, select the GOLF COACH app target, open Info, and add Privacy - Microphone Usage Description."
        }

        if !UIImagePickerController.isSourceTypeAvailable(.camera) {
            return "This device does not have an available camera. Use Import / Add Video in the Simulator, or test capture on a real iPhone."
        }

        return nil
    }

    private static func missingInfoPlistValue(for key: String) -> Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return true
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum LessonReminderScheduler {
    static func schedule(student: Student, lesson: LessonAppointment) async -> String? {
        guard let offset = lesson.reminderLeadTime.notificationOffset else { return nil }

        let reminderDate = lesson.scheduledAt.addingTimeInterval(-offset)
        guard reminderDate > .now else { return nil }

        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { return nil }

            if let existingIdentifier = lesson.notificationIdentifier {
                center.removePendingNotificationRequests(withIdentifiers: [existingIdentifier])
            }

            let content = UNMutableNotificationContent()
            content.title = "Upcoming Golf Lesson"
            content.body = "\(student.name) has \(lesson.title.lowercased()) on \(lesson.scheduledAt.formatted(date: .abbreviated, time: .shortened))."
            content.sound = .default

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let identifier = UUID().uuidString
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            try await center.add(request)
            return identifier
        } catch {
            return nil
        }
    }
}

enum CurrencyFormatter {
    static func string(from decimal: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Locale.current.currency?.identifier ?? "USD"
        return formatter.string(from: decimal as NSDecimalNumber) ?? "\(decimal)"
    }
}

enum StudentAccountStatementFormatter {
    static func message(for student: Student, latestCharge: LessonCharge? = nil) -> String {
        let studentName = student.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let greeting = studentName.isEmpty ? "Hello" : "Hi \(studentName)"
        var lines = [
            "\(greeting), your Golf Coach account has been updated.",
            "",
            "Account statement"
        ]

        if let latestCharge {
            lines.append(
                "New charge: \(chargeLine(for: latestCharge))"
            )
            lines.append("")
        }

        for package in student.packages.sorted(by: { $0.purchaseDate < $1.purchaseDate }) {
            let paymentMethod = package.paymentMethod.map { " via \($0.rawValue)" } ?? ""
            lines.append(
                "\(package.packageType.rawValue) - Paid \(CurrencyFormatter.string(from: package.totalPaid))\(paymentMethod)"
            )

            let sortedCharges = package.charges.sorted { $0.chargedAt < $1.chargedAt }
            if sortedCharges.isEmpty {
                if package.lessonsUsed > 0 {
                    lines.append(
                        "- Earlier lesson charges: \(CurrencyFormatter.string(from: package.amountDeducted))"
                    )
                } else {
                    lines.append("- No session charges recorded")
                }
            } else {
                for charge in sortedCharges {
                    lines.append("- \(chargeLine(for: charge))")
                    let notes = charge.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !notes.isEmpty {
                        lines.append("  Note: \(notes)")
                    }
                }
            }
            lines.append("  Package balance: \(CurrencyFormatter.string(from: package.remainingValue))")
            lines.append("")
        }

        let totalCharged = student.packages.reduce(Decimal.zero) { $0 + $1.amountDeducted }
        lines.append("Total paid: \(CurrencyFormatter.string(from: student.totalPaid))")
        lines.append("Total charged: \(CurrencyFormatter.string(from: totalCharged))")
        lines.append("Remaining credit: \(CurrencyFormatter.string(from: student.remainingValue))")
        return lines.joined(separator: "\n")
    }

    private static func chargeLine(for charge: LessonCharge) -> String {
        let date = charge.chargedAt.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted)
        )
        let playerLabel = charge.participantCount == 1 ? "player" : "players"
        return "\(date): \(charge.durationMinutes) min, \(charge.participantCount) \(playerLabel) - \(CurrencyFormatter.string(from: charge.amount))"
    }
}

struct CameraImagePicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraImagePicker
        init(_ parent: CameraImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct VideoShareView: View {
    let videoURL: URL?
    let notesText: String
    @Environment(\.dismiss) private var dismiss
    @State private var isSharingVideo = false
    @State private var notesCopied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Copy the notes below, share the video, then paste into your message.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.top, 12)

                Divider()
                    .padding(.top, 12)

                ScrollView {
                    Text(notesText.isEmpty ? "No notes for this video." : notesText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }

                Divider()

                VStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = notesText
                        notesCopied = true
                    } label: {
                        Label(
                            notesCopied ? "Notes Copied!" : "Copy Notes",
                            systemImage: notesCopied ? "checkmark.circle.fill" : "doc.on.doc"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(notesCopied ? .green : .primary)

                    if videoURL != nil {
                        Button {
                            isSharingVideo = true
                        } label: {
                            Label("Share Video", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            }
            .navigationTitle("Send to Student")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isSharingVideo) {
                if let url = videoURL {
                    ShareSheet(activityItems: [url])
                        .presentationDetents([.medium, .large])
                }
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootView = scene.windows.first?.rootViewController?.view {
            controller.popoverPresentationController?.sourceView = rootView
            controller.popoverPresentationController?.sourceRect = CGRect(
                x: rootView.bounds.midX, y: rootView.bounds.midY, width: 0, height: 0
            )
            controller.popoverPresentationController?.permittedArrowDirections = []
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ContentView()
        .modelContainer(for: [Student.self, LessonPackage.self, LessonCharge.self, LessonAppointment.self, LessonVideo.self, LessonSessionNote.self], inMemory: true)
}
