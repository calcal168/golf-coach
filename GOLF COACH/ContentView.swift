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
import ReplayKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import UIKit

struct ContentView: View {
    @State private var selectedVideo: VideoPlaybackSelection?
    @State private var selectedCoachAnalysis: CoachAnalysisPlaybackSelection?
    @State private var isPreparingVideo = false
    @State private var isPreparingCoachAnalysis = false

    var body: some View {
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

struct StudentDirectoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Student.name) private var students: [Student]
    let onPlayVideo: (LessonVideo, Student) -> Void
    let onPlayCoachAnalysis: (CoachAnalysisVideo) -> Void
    @State private var isExportingStudents = false
    @State private var navigationPath: [Student] = []
    @State private var highlightedStudentID: PersistentIdentifier?
    @State private var selectedStudentPrompt: String?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                if students.isEmpty {
                    ContentUnavailableView(
                        "No Students Yet",
                        systemImage: "figure.golf",
                        description: Text("Add a student to start tracking lessons, payments, notes, and videos.")
                    )
                } else {
                    ForEach(students) { student in
                        Button {
                            openStudent(student)
                        } label: {
                            StudentRow(
                                student: student,
                                isHighlighted: highlightedStudentID == student.persistentModelID
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteStudents)
                }
            }
            .navigationTitle("Golf Coach")
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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isExportingStudents = true
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(students.isEmpty)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: addStudent) {
                        Label("Add Student", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isExportingStudents) {
                StudentExportView(students: students)
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

    private func deleteStudents(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(students[index])
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(student.name)
                    .font(.headline)
                Spacer()
                Text("\(student.remainingLessons) left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(student.remainingLessons > 0 ? .green : .secondary)
            }

            HStack(spacing: 12) {
                if !student.phoneNumber.isEmpty {
                    Label(student.phoneNumber, systemImage: "phone")
                }
                if !student.email.isEmpty {
                    Label(student.email, systemImage: "envelope")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(isHighlighted ? Color.blue.opacity(0.16) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .animation(.easeInOut(duration: 0.12), value: isHighlighted)
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

struct StudentDetailView: View {
    @Bindable var student: Student
    let onPlayVideo: (LessonVideo, Student) -> Void
    let onPlayCoachAnalysis: (CoachAnalysisVideo) -> Void
    @State private var name: String
    @State private var phoneNumber: String
    @State private var email: String
    @State private var historyNotes: String
    @State private var focusAreas: String
    @State private var isAddingPackage = false
    @State private var isAddingLesson = false
    @State private var isAddingVideo = false
    @State private var isCapturingSwingVideo = false
    @State private var videoCaptureError: String?
    @State private var isShowingVideoCaptureError = false

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
        _historyNotes = State(initialValue: student.historyNotes)
        _focusAreas = State(initialValue: student.focusAreas)
    }

    var body: some View {
        Form {
            Section("Student Information") {
                TextField("Name", text: $name)
                TextField("Phone", text: $phoneNumber)
                    .keyboardType(.phonePad)
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)

                Button {
                    saveStudentDetails()
                } label: {
                    Label("Save Student Information", systemImage: "checkmark.circle")
                }
                .disabled(!hasUnsavedStudentDetails)
            }

            Section("Notes") {
                TextField("History", text: $historyNotes, axis: .vertical)
                    .lineLimit(3...8)
                TextField("Current swing problems and goals", text: $focusAreas, axis: .vertical)
                    .lineLimit(3...8)

                Button {
                    saveStudentDetails()
                } label: {
                    Label("Save Notes", systemImage: "checkmark.circle")
                }
                .disabled(!hasUnsavedStudentDetails)
            }

            Section("Account") {
                LabeledContent("Lessons Remaining", value: "\(student.remainingLessons)")
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
            }

            PackageListSection(student: student)
            LessonListSection(student: student)
            VideoListSection(
                student: student,
                onCaptureVideo: startVideoCapture,
                onAddVideo: { isAddingVideo = true },
                onPlayVideo: onPlayVideo
            )
            CoachAnalysisVideoSection(student: student, onPlayCoachAnalysis: onPlayCoachAnalysis)
        }
        .navigationTitle(student.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { startVideoCapture() } label: {
                    Label("Capture Video", systemImage: "camera.fill")
                }
            }
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
        .alert("Video Capture Failed", isPresented: $isShowingVideoCaptureError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(videoCaptureError ?? "The video could not be saved.")
        }
    }

    private var hasUnsavedStudentDetails: Bool {
        name != student.name ||
        phoneNumber != student.phoneNumber ||
        email != student.email ||
        historyNotes != student.historyNotes ||
        focusAreas != student.focusAreas
    }

    private func saveStudentDetails() {
        student.name = name
        student.phoneNumber = phoneNumber
        student.email = email
        student.historyNotes = historyNotes
        student.focusAreas = focusAreas
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
                title: "Swing Video",
                recordedAt: .now,
                notes: "",
                fileURLString: VideoFileStore.persistedFileName(for: savedURL),
                lessonDate: .now,
                focusNotes: student.focusAreas,
                problemNotes: student.historyNotes,
                comparisonNotes: "Compare this swing to the previous lesson."
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
                            Text("\(package.remainingLessons)/\(package.lessonsPurchased) left")
                                .font(.subheadline.weight(.semibold))
                        }

                        ProgressView(value: Double(package.lessonsUsed), total: Double(max(package.lessonsPurchased, 1)))

                        HStack {
                            Text("Paid \(CurrencyFormatter.string(from: package.totalPaid))")
                            Spacer()
                            Text("Used \(CurrencyFormatter.string(from: package.amountDeducted))")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Button {
                            if package.remainingLessons > 0 {
                                package.lessonsUsed += 1
                            }
                        } label: {
                            Label("Deduct Lesson", systemImage: "minus.circle")
                        }
                        .disabled(package.remainingLessons == 0)
                    }
                    .padding(.vertical, 6)
                }
                .onDelete { offsets in
                    for index in offsets {
                        student.packages.removeAll { $0.persistentModelID == sortedPackages[index].persistentModelID }
                    }
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
                            defaultFocusNotes: student.focusAreas,
                            defaultProblemNotes: student.historyNotes,
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
                    playWhenReady()
                }
                .onDisappear {
                    player.pause()
                }
        }
    }

    private func playWhenReady() {
        Task { @MainActor in
            player.pause()
            guard await VideoPlaybackReadiness.waitUntilReady(player.currentItem) else { return }
            await player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            player.playImmediately(atRate: 1.0)
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
                if let url = video.fileURL {
                    ShareLink(item: url) {
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
                        let package = LessonPackage(
                            packageType: packageType,
                            lessonsPurchased: lessonsPurchased,
                            totalPaid: Decimal(totalPaid),
                            purchaseDate: purchaseDate
                        )
                        student.packages.append(package)
                        dismiss()
                    }
                }
            }
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

struct AddVideoView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var student: Student
    @State private var title = "Swing Video"
    @State private var lessonDate: Date
    @State private var notes = ""
    @State private var focusNotes: String
    @State private var problemNotes: String
    @State private var comparisonNotes = ""
    @State private var showCamera = false
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var pendingVideoURL: URL?
    @State private var importError: String?

    init(student: Student) {
        self.student = student
        _lessonDate = State(initialValue: .now)
        _focusNotes = State(initialValue: student.focusAreas)
        _problemNotes = State(initialValue: student.historyNotes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Lesson") {
                    TextField("Title", text: $title)
                    DatePicker("Lesson Date", selection: $lessonDate)
                    TextField("What the student is improving", text: $focusNotes, axis: .vertical)
                        .lineLimit(3...8)
                    TextField("Existing problem", text: $problemNotes, axis: .vertical)
                        .lineLimit(3...8)
                    TextField("Comparison to last lesson", text: $comparisonNotes, axis: .vertical)
                        .lineLimit(3...8)
                    TextField("Extra analysis notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
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
                            title: title,
                            recordedAt: lessonDate,
                            notes: notes,
                            fileURLString: pendingVideoURL.map(VideoFileStore.persistedFileName),
                            lessonDate: lessonDate,
                            focusNotes: focusNotes,
                            problemNotes: problemNotes,
                            comparisonNotes: comparisonNotes
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

    var body: some View {
        NavigationStack {
            List(students) { student in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(student.name)
                            .font(.headline)
                        Spacer()
                        Text("\(student.remainingLessons) lessons")
                            .font(.subheadline.weight(.semibold))
                    }
                    HStack {
                        Text("Paid: \(CurrencyFormatter.string(from: student.totalPaid))")
                        Spacer()
                        if let package = student.activePackage {
                            Text("Balance: \(CurrencyFormatter.string(from: package.remainingValue))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Payments")
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
                    isDrawingEnabled: isDrawingEnabled
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
            return gestureRecognizer.numberOfTouches == 1
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
    @State private var isShowingColors = false

    var body: some View {
        VStack(spacing: 10) {
            toolButton(.line, title: "Line", systemImage: "slash")
            toolButton(.circle, title: "Circle", systemImage: "circle")

            Divider()
                .frame(width: 58)
                .overlay(.white.opacity(0.35))

            Button {
                isShowingColors.toggle()
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(selectedColor.color)
                        .frame(width: 16, height: 16)
                    Text("Color")
                        .font(.caption2.weight(.bold))
                }
                .frame(width: 72, height: 42)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(Color.black.opacity(0.72))
            .clipShape(Capsule())

            if isShowingColors {
                ForEach(SwingDrawingColor.allCases) { color in
                    Button {
                        selectedColor = color
                        isShowingColors = false
                    } label: {
                        Circle()
                            .fill(color.color)
                            .frame(width: 34, height: 34)
                            .overlay {
                                Circle()
                                    .stroke(selectedColor == color ? Color.white : Color.black.opacity(0.35), lineWidth: selectedColor == color ? 3 : 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(color.rawValue) drawing color")
                }
            }

            Divider()
                .frame(width: 58)
                .overlay(.white.opacity(0.35))

            Button(action: onUndo) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.uturn.backward")
                    Text("Undo")
                        .font(.caption2.weight(.bold))
                }
                .frame(width: 72, height: 42)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(canUndo ? Color.black.opacity(0.72) : Color.black.opacity(0.28))
            .clipShape(Capsule())
            .disabled(!canUndo)
        }
        .padding(8)
        .background(.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .contentShape(RoundedRectangle(cornerRadius: 22))
        .allowsHitTesting(true)
    }

    private func toolButton(_ tool: SwingDrawingTool, title: String, systemImage: String) -> some View {
        Button {
            selectedTool = tool
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                Text(title)
                    .font(.caption2.weight(.bold))
            }
            .frame(width: 78, height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(selectedTool == tool ? .black : .white)
        .background(selectedTool == tool ? Color.yellow : Color.black.opacity(0.72))
        .clipShape(Capsule())
        .accessibilityLabel(tool.rawValue)
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
                    ZStack(alignment: .trailing) {
                        ControlledVideoPlayer(player: player, showsPlaybackControls: !isDrawingMode)
                            .background(.black)

                        SwingDrawingOverlay(
                            strokes: $strokes,
                            currentStroke: $currentStroke,
                            selectedTool: $selectedDrawingTool,
                            selectedColor: $selectedDrawingColor,
                            isDrawingEnabled: isDrawingMode,
                            onUndo: undoLastStroke
                        )

                        if isDrawingMode {
                            DrawingToolPalette(
                                selectedTool: $selectedDrawingTool,
                                selectedColor: $selectedDrawingColor,
                                canUndo: !strokes.isEmpty,
                                onUndo: undoLastStroke
                            )
                            .padding(.trailing, 12)
                        }

                        if isRecordingCoachAnalysis {
                            VStack {
                                HStack {
                                    Label("Recording Coach Analysis", systemImage: "record.circle.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(.red, in: Capsule())
                                    Spacer()
                                }
                                Spacer()
                            }
                            .padding()
                        }
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
                                toggleCoachAnalysisRecording()
                            } label: {
                                Label(
                                    isRecordingCoachAnalysis ? "Stop Coach Analysis Recording" : "Start Coach Analysis Recording",
                                    systemImage: isRecordingCoachAnalysis ? "stop.circle.fill" : "record.circle"
                                )
                            }

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

                    if isShowingInlineTrimControls {
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
                    } else if hasActiveTrim {
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
                playWhenReady()
            }
            .task {
                await trackPlaybackTime()
            }
            .onDisappear {
                saveDrawingStrokes()
                player?.pause()
                removeTrimEndBoundaryObserver()
                removePlaybackProgressObserver()
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
                    notes: "Analysis for \(video.title)"
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

    private var playbackStartSeconds: Double {
        clampedTrimStart(video.trimStartSeconds ?? activeTrimStartSeconds)
    }

    private func playWhenReady() {
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
            player.playImmediately(atRate: playbackRate)
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

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = showsPlaybackControls
        controller.view.isUserInteractionEnabled = showsPlaybackControls
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.player = player
        controller.showsPlaybackControls = showsPlaybackControls
        controller.view.isUserInteractionEnabled = showsPlaybackControls
    }
}

struct VideoReviewControls: View {
    @Binding var currentTime: Double
    let duration: Double
    let playbackRate: Float
    let frameRate: Float
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
            "History Notes",
            "Current Problems / Goals",
            "Lessons Paid For",
            "Lessons Used",
            "Lessons Remaining",
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
                student.historyNotes,
                student.focusAreas,
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

#Preview {
    ContentView()
        .modelContainer(for: [Student.self, LessonPackage.self, LessonAppointment.self, LessonVideo.self], inMemory: true)
}
