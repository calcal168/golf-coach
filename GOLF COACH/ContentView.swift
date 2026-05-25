//
//  ContentView.swift
//  GOLF COACH
//
//  Created by Calvin Deng on 2026-05-19.
//

import EventKit
import EventKitUI
import MessageUI
import PhotosUI
import Photos
import AVKit
import AVFoundation
import LocalAuthentication
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

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("selectedAppLanguage") private var selectedAppLanguage = AppLanguage.english.rawValue
    @AppStorage("prefersDarkMode") private var prefersDarkMode = false
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
            authenticate()
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
        TabView {
            StudentDirectoryView(
                onPlayVideo: openVideo,
                onPlayCoachAnalysis: openCoachAnalysis
            )
                .tabItem { Label("Students", systemImage: "person.2") }

            ScheduleView()
                .tabItem { Label("Schedule", systemImage: "calendar") }

            PaymentsView()
                .tabItem { Label("Payments", systemImage: "creditcard") }

            VideoLibraryView(onPlayVideo: openVideo)
                .tabItem { Label("Videos", systemImage: "video") }
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
            SimpleVideoPlayerSheet(title: selection.analysis.title, url: selection.url)
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
        guard let url = analysis.fileURL else {
            print("DEBUG ContentView selectedCoachAnalysis ignored missing file: \(analysis.title)")
            return
        }

        guard selectedCoachAnalysis == nil, !isPreparingCoachAnalysis else {
            print("DEBUG ContentView selectedCoachAnalysis ignored duplicate tap: \(analysis.title)")
            return
        }

        isPreparingCoachAnalysis = true
        selectedCoachAnalysis = CoachAnalysisPlaybackSelection(analysis: analysis, url: url)
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
                    onPlayCoachAnalysis: onPlayCoachAnalysis
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
                        message: "Student profiles, packages, and appointments were saved. Video files are not included in this backup."
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
                message: "\(backupPendingRestore.students.count) student record(s) restored. Video files are not included in student backups."
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
            return "Undo Session Charge"
        case .packageDeletion:
            return "Undo Package Delete"
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
    @State private var name: String
    @State private var phoneNumber: String
    @State private var email: String
    @State private var age: String
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
    @State private var isCapturingSwingVideo = false
    @State private var videoCaptureError: String?
    @State private var isShowingVideoCaptureError = false
    @State private var sessionNoteToShare: LessonSessionNote?
    @State private var isAddingSessionNote = false
    @State private var sessionNoteDefaultDate: Date = .now
    @State private var sessionNoteForEditing: LessonSessionNote?
    @State private var sessionVideoForEditing: LessonVideo?
    @State private var sessionAnalysisForEditing: CoachAnalysisVideo?
    @State private var packageToDeduct: LessonPackage?
    @State private var lessonMessageBody = ""
    @State private var isShowingLessonMessageComposer = false
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
    @State private var undoStatusMessage: String?
    @State private var isShowingUndoStatus = false

    init(
        student: Student,
        onPlayVideo: @escaping (LessonVideo, Student) -> Void,
        onPlayCoachAnalysis: @escaping (CoachAnalysisVideo) -> Void
    ) {
        self.student = student
        self.onPlayVideo = onPlayVideo
        self.onPlayCoachAnalysis = onPlayCoachAnalysis
        _name = State(initialValue: student.name)
        _phoneNumber = State(initialValue: student.phoneNumber)
        _email = State(initialValue: student.email)
        _age = State(initialValue: student.age ?? "")
        _yearsOfExperience = State(initialValue: student.yearsOfExperience ?? "")
        _handicap = State(initialValue: student.handicap ?? "")
        _golfGoal = State(initialValue: student.golfGoal ?? "")
        _jobInfo = State(initialValue: student.jobInfo ?? "")
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
            AddVideoView(student: student)
        }
        .fullScreenCover(isPresented: $isCapturingSwingVideo) {
            VideoCaptureView { url in
                saveCapturedSwingVideo(from: url)
            }
            .ignoresSafeArea()
        }
        .sheet(item: $sessionNoteToShare) { note in
            SessionNoteShareView(note: note, studentName: student.name)
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
        .sheet(isPresented: $isShowingLessonMessageComposer) {
            MessageComposerView(
                recipients: [student.phoneNumber],
                body: lessonMessageBody,
                onFinish: { resultMessage in
                    if let resultMessage {
                        lessonStatusMessage = resultMessage
                        isShowingLessonStatus = true
                    }
                }
            )
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
            LessonListSection(student: student)
            LessonSessionsSection(
                student: student,
                onCaptureVideo: startVideoCapture,
                onAddVideo: { isAddingVideo = true },
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
        .onChange(of: age) { saveStudentDetails() }
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
            LabeledContent("Age") {
                TextField("e.g. 18", text: $age)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
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
                LabeledContent("Active Package", value: activePackage.packageType.rawValue)
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
                prepareAccountStatementText()
            } label: {
                Label("Text Account Statement", systemImage: "message")
            }

            if let lastUndoAction {
                Button {
                    undoLastAction()
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
            onRequestDelete: { packages in
                stagePackagesForDeletion(packages)
            }
        )
    }

    private var videoSection: some View {
        VideoListSection(
            student: student,
            onCaptureVideo: startVideoCapture,
            onAddVideo: { isAddingVideo = true },
            onPlayVideo: onPlayVideo
        )
    }

    private func recordSessionCharge(_ charge: LessonCharge, from package: LessonPackage) {
        guard charge.amount > 0, charge.amount <= package.remainingValue else { return }
        package.charges.append(charge)
        package.lessonsUsed += 1
        lastUndoAction = .lessonCharge(package, charge)
        packageToDeduct = nil

        prepareAccountStatementText(latestCharge: charge)
    }

    private func prepareAccountStatementText(latestCharge: LessonCharge? = nil) {
        lessonMessageBody = StudentAccountStatementFormatter.message(for: student, latestCharge: latestCharge)

        if student.phoneNumber.trimmingCharacters(in: .whitespaces).isEmpty {
            lessonStatusMessage = "Unable to prepare account statement because \(student.name) has no phone number on file."
            isShowingLessonStatus = true
            return
        }

        guard MFMessageComposeViewController.canSendText() else {
            lessonStatusMessage = "This device cannot send text messages. Try on a physical iPhone."
            isShowingLessonStatus = true
            return
        }

        if latestCharge != nil {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                isShowingLessonMessageComposer = true
            }
        } else {
            isShowingLessonMessageComposer = true
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

    private func saveStudentDetails() {
        student.name = name
        student.phoneNumber = phoneNumber
        student.email = email
        student.age = age
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

    private func startVideoCapture() {
        if let issue = VideoCaptureReadiness.blockingIssue {
            videoCaptureError = issue
            isShowingVideoCaptureError = true
            return
        }

        isCapturingSwingVideo = true
    }

    private func saveCapturedSwingVideo(from url: URL) {
        do {
            let savedURL = try VideoFileStore.copyVideo(from: url)
            let video = LessonVideo(
                title: "Lesson Video — \(Date.now.formatted(date: .abbreviated, time: .omitted))",
                recordedAt: .now,
                fileURLString: VideoFileStore.persistedFileName(for: savedURL),
                lessonDate: .now
            )
            student.videos.append(video)
        } catch {
            videoCaptureError = error.localizedDescription
            isShowingVideoCaptureError = true
        }
    }
}

struct PackageListSection: View {
    @Bindable var student: Student
    let onRequestDeduct: (LessonPackage) -> Void
    let onRequestDelete: ([LessonPackage]) -> Void

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
                            Text(package.packageType.rawValue)
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

                        if !package.charges.isEmpty {
                            ForEach(package.charges.sorted { $0.chargedAt > $1.chargedAt }.prefix(3)) { charge in
                                HStack {
                                    Text(charge.chargedAt, format: .dateTime.month().day())
                                    Text("\(charge.durationMinutes) min")
                                    Text("\(charge.participantCount) player(s)")
                                    Spacer()
                                    Text(CurrencyFormatter.string(from: charge.amount))
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }

                        Button {
                            onRequestDeduct(package)
                        } label: {
                            Label("Record Session Charge", systemImage: "minus.circle")
                        }
                        .disabled(package.remainingValue <= 0)
                    }
                    .padding(.vertical, 6)
                }
                .onDelete { offsets in
                    onRequestDelete(offsets.map { sortedPackages[$0] })
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
            .navigationTitle("Record Session Charge")
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
        student.videos.sorted { $0.recordedAt > $1.recordedAt }
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
                        }

                        Spacer()

                        if let url = analysis.fileURL {
                            Button {
                                openAnalysis(analysis)
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
                .onDelete(perform: deleteAnalyses)
            }
        }
        .listRowBackground(StudentDetailSectionTint.coachAnalysis)
    }

    private func openAnalysis(_ analysis: CoachAnalysisVideo) {
        guard analysis.fileURL != nil else {
            print("DEBUG CoachAnalysisVideoSection selectedCoachAnalysis ignored missing file: \(analysis.title)")
            return
        }

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

struct SimpleVideoPlayerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let url: URL
    @State private var player: AVPlayer

    init(title: String, url: URL) {
        self.title = title
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        NavigationStack {
            ControlledVideoPlayer(player: player, showsPlaybackControls: true)
                .background(.black)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            player.pause()
                            dismiss()
                        }
                    }

                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: url) {
                            Label("Send", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                .onAppear {
                    prepareForPlayback()
                }
                .onDisappear {
                    player.pause()
                }
        }
    }

    private func prepareForPlayback() {
        Task { @MainActor in
            player.pause()
            guard await VideoPlaybackReadiness.waitUntilReady(player.currentItem) else { return }
            await player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        }
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
        for video in student.videos {
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

    var hasContent: Bool {
        !note.focus.isEmpty || !note.problems.isEmpty || !note.improvements.isEmpty || !note.generalNotes.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !hasContent {
                Text("No notes added yet")
                    .foregroundStyle(.secondary)
                    .italic()
                    .font(.subheadline)
            } else {
                if !note.focus.isEmpty { SessionNoteField(label: "Today's Focus", text: note.focus) }
                if !note.problems.isEmpty { SessionNoteField(label: "Problem Areas", text: note.problems) }
                if !note.improvements.isEmpty { SessionNoteField(label: "Areas to Improve", text: note.improvements) }
                if !note.generalNotes.isEmpty { SessionNoteField(label: "Additional Notes", text: note.generalNotes) }
            }

            HStack(spacing: 16) {
                Button(action: onEdit) {
                    Label("Edit Notes", systemImage: "pencil")
                }
                .font(.caption)
                .buttonStyle(.borderless)

                Button(action: onShare) {
                    Label("Share Notes", systemImage: "square.and.arrow.up")
                }
                .font(.caption)
                .buttonStyle(.borderless)

                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}

struct SessionNoteField: View {
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            }

            Spacer()

            HStack(spacing: 12) {
                Button(action: onEdit) {
                    Image(systemName: "pencil.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)

                if analysis.fileURL != nil {
                    Button(action: onPlay) {
                        Image(systemName: "play.circle")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 4)
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

struct EditSessionNoteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let student: Student?
    let existingNote: LessonSessionNote?

    @State private var sessionDate: Date
    @State private var focus: String
    @State private var problems: String
    @State private var improvements: String
    @State private var generalNotes: String

    init(student: Student, defaultDate: Date = .now) {
        self.student = student
        self.existingNote = nil
        _sessionDate = State(initialValue: Calendar.current.startOfDay(for: defaultDate))
        _focus = State(initialValue: "")
        _problems = State(initialValue: "")
        _improvements = State(initialValue: "")
        _generalNotes = State(initialValue: "")
    }

    init(existingNote: LessonSessionNote) {
        self.student = nil
        self.existingNote = existingNote
        _sessionDate = State(initialValue: existingNote.sessionDate)
        _focus = State(initialValue: existingNote.focus)
        _problems = State(initialValue: existingNote.problems)
        _improvements = State(initialValue: existingNote.improvements)
        _generalNotes = State(initialValue: existingNote.generalNotes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Lesson Date", selection: $sessionDate, displayedComponents: .date)
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
        }
    }

    private func save() {
        if let note = existingNote {
            note.sessionDate = sessionDate
            note.focus = focus
            note.problems = problems
            note.improvements = improvements
            note.generalNotes = generalNotes
        } else if let student {
            let note = LessonSessionNote(
                sessionDate: sessionDate,
                focus: focus,
                problems: problems,
                improvements: improvements,
                generalNotes: generalNotes
            )
            student.sessionNotes.append(note)
        }
        dismiss()
    }
}

struct SessionNoteShareView: View {
    let note: LessonSessionNote
    let studentName: String
    @Environment(\.dismiss) private var dismiss

    var formattedText: String {
        let dateStr = note.sessionDate.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        let greeting = studentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Hi" : "Hi \(studentName.trimmingCharacters(in: .whitespacesAndNewlines))"
        var parts: [String] = [
            "Golf Lesson Summary — \(dateStr)",
            "\(greeting), here are your notes from today's lesson."
        ]
        if !note.focus.isEmpty { parts.append("TODAY'S FOCUS\n\(note.focus)") }
        if !note.problems.isEmpty { parts.append("PROBLEM AREAS\n\(note.problems)") }
        if !note.improvements.isEmpty { parts.append("AREAS TO IMPROVE\n\(note.improvements)") }
        if !note.generalNotes.isEmpty { parts.append("ADDITIONAL NOTES\n\(note.generalNotes)") }
        return parts.joined(separator: "\n\n")
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

                Button {
                    presentShareSheet()
                } label: {
                    Label("Send Notes", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
            .navigationTitle("Share Lesson Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func presentShareSheet() {
        let image = renderNotesAsImage(formattedText)
        let source = NoteShareItemSource(text: formattedText, image: image)
        let controller = UIActivityViewController(activityItems: [source], applicationActivities: nil)
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

struct AddPackageView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var student: Student
    @State private var packageType = LessonPackageType.fiveLesson
    @State private var lessonsPurchased = 5
    @State private var totalPaid = 0.0
    @State private var purchaseDate = Date.now
    @State private var hasSavedPackage = false
    @State private var messageRecipients: [String] = []
    @State private var messageBody = ""
    @State private var isShowingMessageComposer = false
    @State private var saveStatusMessage: String?
    @State private var isShowingSaveStatus = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Package", selection: $packageType) {
                    ForEach(LessonPackageType.allCases) { type in
                        Text(type.rawValue).tag(type)
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
                DatePicker("Purchase Date", selection: $purchaseDate, displayedComponents: .date)
            }
            .navigationTitle("New Payment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        savePackageAndTextBalance()
                    }
                    .disabled(hasSavedPackage)
                }
            }
            .sheet(isPresented: $isShowingMessageComposer) {
                MessageComposerView(
                    recipients: messageRecipients,
                    body: messageBody,
                    onFinish: { _ in
                        dismiss()
                    }
                )
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

    private func savePackageAndTextBalance() {
        guard !hasSavedPackage else { return }

        let package = LessonPackage(
            packageType: packageType,
            lessonsPurchased: lessonsPurchased,
            totalPaid: Decimal(totalPaid),
            purchaseDate: purchaseDate
        )
        student.packages.append(package)
        hasSavedPackage = true

        let phoneNumber = student.phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        messageRecipients = [phoneNumber]
        messageBody = StudentAccountStatementFormatter.message(for: student)

        guard !phoneNumber.isEmpty else {
            saveStatusMessage = "Payment saved, but \(student.name) has no phone number on file."
            isShowingSaveStatus = true
            return
        }

        guard MFMessageComposeViewController.canSendText() else {
            saveStatusMessage = "Payment saved, but this device cannot send text messages. Try on a physical iPhone."
            isShowingSaveStatus = true
            return
        }

        isShowingMessageComposer = true
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

struct AddVideoView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var student: Student
    @State private var lessonDate = Date.now
    @State private var showCamera = false
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var pendingVideoURL: URL?
    @State private var importError: String?

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

                    PhotosPicker(selection: $selectedVideoItem, matching: .videos) {
                        Label("Import from Photos", systemImage: "photo.on.rectangle")
                    }

                    if let pendingVideoURL {
                        Label(pendingVideoURL.lastPathComponent, systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
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
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let video = LessonVideo(
                            title: autoTitle,
                            recordedAt: lessonDate,
                            fileURLString: pendingVideoURL.map(VideoFileStore.persistedFileName),
                            lessonDate: lessonDate
                        )
                        student.videos.append(video)
                        dismiss()
                    }
                    .disabled(pendingVideoURL == nil)
                }
            }
            .sheet(isPresented: $showCamera) {
                VideoCaptureView { url in
                    do {
                        pendingVideoURL = try VideoFileStore.copyVideo(from: url)
                    } catch {
                        importError = error.localizedDescription
                    }
                }
            }
            .onChange(of: selectedVideoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    do {
                        pendingVideoURL = try await VideoFileStore.saveVideo(from: newItem)
                    } catch {
                        importError = error.localizedDescription
                    }
                }
            }
        }
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
    @State private var chargeMessageBody = ""
    @State private var chargeMessageRecipients: [String] = []
    @State private var isShowingChargeMessageComposer = false
    @State private var chargeStatusMessage: String?
    @State private var isShowingChargeStatus = false

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

                                Spacer()

                                Button {
                                    studentForLesson = student
                                } label: {
                                    Label("Schedule", systemImage: "calendar.badge.plus")
                                }
                            }
                            .font(.caption.weight(.semibold))

                            if let package = student.activePackage {
                                Button {
                                    studentForCharge = student
                                    packageForCharge = package
                                } label: {
                                    Label("Record Session Charge", systemImage: "minus.circle")
                                }
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
                    prepareChargeMessage(for: charge)
                }
            }
            .sheet(isPresented: $isShowingChargeMessageComposer) {
                MessageComposerView(
                    recipients: chargeMessageRecipients,
                    body: chargeMessageBody,
                    onFinish: { resultMessage in
                        if let resultMessage {
                            chargeStatusMessage = resultMessage
                            isShowingChargeStatus = true
                        }
                    }
                )
            }
            .alert("Lesson Update", isPresented: $isShowingChargeStatus, presenting: chargeStatusMessage) { _ in
                Button("OK", role: .cancel) { }
            } message: { message in
                Text(message)
            }
        }
    }

    private func prepareChargeMessage(for charge: LessonCharge) {
        guard let student = studentForCharge else { return }
        chargeMessageBody = StudentAccountStatementFormatter.message(
            for: student,
            latestCharge: charge
        )
        let phoneNumber = student.phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phoneNumber.isEmpty else {
            chargeStatusMessage = "Session charge saved, but \(student.name) has no phone number on file."
            isShowingChargeStatus = true
            return
        }
        guard MFMessageComposeViewController.canSendText() else {
            chargeStatusMessage = "Session charge saved, but this device cannot send text messages. Try on a physical iPhone."
            isShowingChargeStatus = true
            return
        }

        chargeMessageRecipients = [phoneNumber]
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            isShowingChargeMessageComposer = true
        }
    }
}

struct VideoLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Student.name) private var students: [Student]
    let onPlayVideo: (LessonVideo, Student) -> Void

    var videos: [(student: Student, video: LessonVideo)] {
        students.flatMap { student in
            student.videos.map { (student, $0) }
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
    let url: URL

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
                                ControlledVideoPlayer(player: player, showsPlaybackControls: !isDrawingMode)
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
                        Button {
                            toggleCoachAnalysisRecording()
                        } label: {
                            Label(
                                isRecordingCoachAnalysis ? "Stop Coach Analysis Recording" : "Start Coach Analysis Recording",
                                systemImage: isRecordingCoachAnalysis ? "stop.circle.fill" : "record.circle"
                            )
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.red)
                        }
                        .accessibilityLabel(isRecordingCoachAnalysis ? "Stop coach analysis recording" : "Start coach analysis recording")
                    }

                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                isDrawingMode.toggle()
                                if isDrawingMode {
                                    player?.pause()
                                }
                                saveDrawingStrokes()
                            } label: {
                                Label(isDrawingMode ? "Stop Drawing" : "Draw Lines", systemImage: "pencil.and.outline")
                            }

                            Button {
                                undoLastStroke()
                            } label: {
                                Label("Undo Line", systemImage: "arrow.uturn.backward")
                            }
                            .disabled(strokes.isEmpty)

                            Button(role: .destructive) {
                                clearStrokes()
                            } label: {
                                Label("Clear Lines", systemImage: "trash")
                            }
                            .disabled(strokes.isEmpty)

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
                    VideoReviewControls(
                        currentTime: $currentTimeSeconds,
                        duration: durationSeconds,
                        playbackRate: playbackRate,
                        frameRate: sourceFrameRate,
                        showsDetailedControls: !isRecordingCoachAnalysis,
                        onScrubBegan: {
                            isScrubbing = true
                            player?.pause()
                        },
                        onScrubChanged: { time in
                            seek(to: time)
                        },
                        onScrubEnded: { time in
                            isScrubbing = false
                            seek(to: time)
                        },
                        onRateSelected: { rate in
                            setPlaybackRate(rate)
                        },
                        onStepFrameBackward: {
                            stepFrame(direction: -1)
                        },
                        onStepFrameForward: {
                            stepFrame(direction: 1)
                        },
                        onTrim: {
                            player?.pause()
                            toggleInlineTrimControls()
                        }
                    )

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
        if analysisZoomScale <= 1.01 {
            withAnimation(.easeOut(duration: 0.18)) {
                analysisZoomScale = 1
                analysisZoomOffset = .zero
            }
        }
    }

    private func beginAnalysisZoomPan() {
        analysisZoomStartOffset = analysisZoomOffset
    }

    private func updateAnalysisZoomPan(translation: CGSize, in size: CGSize) {
        guard analysisZoomScale > 1 else { return }

        let proposedOffset = CGSize(
            width: analysisZoomStartOffset.width + translation.width,
            height: analysisZoomStartOffset.height + translation.height
        )
        analysisZoomOffset = clampedAnalysisZoomOffset(proposedOffset, scale: analysisZoomScale, in: size)
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
            try? await Task.sleep(for: .milliseconds(30))
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
        let frameStep = 1 / max(Double(sourceFrameRate), 1)
        seek(to: currentTimeSeconds + (Double(direction) * frameStep))
    }

    private func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        applyPlaybackTrimLimits()
        player?.rate = rate
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
    let name: String
    let phoneNumber: String
    let email: String
    let age: String?
    let yearsOfExperience: String?
    let handicap: String?
    let golfGoal: String?
    let jobInfo: String?
    let createdAt: Date
    let photoData: Data?
    let packages: [LessonPackageBackupRecord]
    let lessons: [LessonAppointmentBackupRecord]
    let sessionNotes: [LessonSessionNoteBackupRecord]

    init(student: Student) {
        name = student.name
        phoneNumber = student.phoneNumber
        email = student.email
        age = student.age
        yearsOfExperience = student.yearsOfExperience
        handicap = student.handicap
        golfGoal = student.golfGoal
        jobInfo = student.jobInfo
        createdAt = student.createdAt
        photoData = student.photoData
        packages = student.packages.map(LessonPackageBackupRecord.init)
        lessons = student.lessons.map(LessonAppointmentBackupRecord.init)
        sessionNotes = student.sessionNotes.map(LessonSessionNoteBackupRecord.init)
    }

    func makeStudent() -> Student {
        Student(
            name: name,
            phoneNumber: phoneNumber,
            email: email,
            age: age,
            yearsOfExperience: yearsOfExperience,
            handicap: handicap,
            golfGoal: golfGoal,
            jobInfo: jobInfo,
            createdAt: createdAt,
            photoData: photoData,
            packages: packages.map { $0.makePackage() },
            lessons: lessons.map { $0.makeLesson() },
            sessionNotes: sessionNotes.map { $0.makeNote() }
        )
    }
}

struct LessonPackageBackupRecord: Codable {
    let packageTypeRawValue: String
    let lessonsPurchased: Int
    let lessonsUsed: Int
    let totalPaid: Decimal
    let purchaseDate: Date
    let charges: [LessonChargeBackupRecord]?

    init(package: LessonPackage) {
        packageTypeRawValue = package.packageTypeRawValue
        lessonsPurchased = package.lessonsPurchased
        lessonsUsed = package.lessonsUsed
        totalPaid = package.totalPaid
        purchaseDate = package.purchaseDate
        charges = package.charges.map(LessonChargeBackupRecord.init)
    }

    func makePackage() -> LessonPackage {
        LessonPackage(
            packageType: LessonPackageType(rawValue: packageTypeRawValue) ?? .custom,
            lessonsPurchased: lessonsPurchased,
            lessonsUsed: lessonsUsed,
            totalPaid: totalPaid,
            purchaseDate: purchaseDate,
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

struct LessonSessionNoteBackupRecord: Codable {
    let sessionDate: Date
    let focus: String
    let problems: String
    let improvements: String
    let generalNotes: String

    init(note: LessonSessionNote) {
        sessionDate = note.sessionDate
        focus = note.focus
        problems = note.problems
        improvements = note.improvements
        generalNotes = note.generalNotes
    }

    func makeNote() -> LessonSessionNote {
        LessonSessionNote(
            sessionDate: sessionDate,
            focus: focus,
            problems: problems,
            improvements: improvements,
            generalNotes: generalNotes
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
            "Age",
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
            "Upcoming Lessons",
            "Saved Videos"
        ]

        let rows = students.map { student in
            let lessonsPaidFor = student.packages.reduce(0) { $0 + $1.lessonsPurchased }
            let lessonsUsed = student.packages.reduce(0) { $0 + $1.lessonsUsed }
            let amountDeducted = student.packages.reduce(Decimal.zero) { $0 + $1.amountDeducted }
            let remainingValue = student.packages.reduce(Decimal.zero) { $0 + $1.remainingValue }
            let upcomingLessons = student.lessons.filter { !$0.isCompleted && $0.scheduledAt >= .now }.count

            return [
                student.name,
                student.phoneNumber,
                student.email,
                student.age ?? "",
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

    static func saveVideo(from item: PhotosPickerItem) async throws -> URL {
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let destination = try makeDestinationURL(fileExtension: "mov")
        try data.write(to: destination, options: .atomic)
        return destination
    }

    static func copyVideo(from url: URL) throws -> URL {
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

    static func makeDestinationURL(fileExtension: String) throws -> URL {
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
            lines.append(
                "\(package.packageType.rawValue) - Paid \(CurrencyFormatter.string(from: package.totalPaid))"
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
