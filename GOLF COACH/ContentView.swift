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
import AVKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import UIKit

struct ContentView: View {
    var body: some View {
        TabView {
            StudentDirectoryView()
                .tabItem { Label("Students", systemImage: "person.2") }

            ScheduleView()
                .tabItem { Label("Schedule", systemImage: "calendar") }

            PaymentsView()
                .tabItem { Label("Payments", systemImage: "creditcard") }

            VideoLibraryView()
                .tabItem { Label("Videos", systemImage: "video") }
        }
    }
}

struct StudentDirectoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Student.name) private var students: [Student]
    @State private var isExportingStudents = false

    var body: some View {
        NavigationStack {
            List {
                if students.isEmpty {
                    ContentUnavailableView(
                        "No Students Yet",
                        systemImage: "figure.golf",
                        description: Text("Add a student to start tracking lessons, payments, notes, and videos.")
                    )
                } else {
                    ForEach(students) { student in
                        NavigationLink(value: student) {
                            StudentRow(student: student)
                        }
                    }
                    .onDelete(perform: deleteStudents)
                }
            }
            .navigationTitle("Golf Coach")
            .navigationDestination(for: Student.self) { student in
                StudentDetailView(student: student)
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

    private func deleteStudents(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(students[index])
        }
    }
}

struct StudentRow: View {
    let student: Student

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
                    Button("Done") { dismiss() }
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

    init(student: Student) {
        self.student = student
        _name = State(initialValue: student.name)
        _phoneNumber = State(initialValue: student.phoneNumber)
        _email = State(initialValue: student.email)
        _historyNotes = State(initialValue: student.historyNotes)
        _focusAreas = State(initialValue: student.focusAreas)
    }

    var body: some View {
        Form {
            Section {
                Button {
                    startVideoCapture()
                } label: {
                    Label("Start Video Capture", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

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
                onAddVideo: { isAddingVideo = true }
            )
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
                fileURLString: savedURL.absoluteString
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
    @Bindable var student: Student
    let onCaptureVideo: () -> Void
    let onAddVideo: () -> Void
    @State private var selectedVideoForPlayback: LessonVideo?

    var sortedVideos: [LessonVideo] {
        student.videos.sorted { $0.recordedAt > $1.recordedAt }
    }

    var body: some View {
        Section("Video History") {
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
                ForEach(sortedVideos) { video in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(video.title, systemImage: "play.rectangle")
                                .font(.headline)
                            Spacer()
                            if let url = video.fileURL {
                                Button {
                                    selectedVideoForPlayback = video
                                } label: {
                                    Label("Play", systemImage: "play.circle")
                                }
                                .font(.caption)

                                ShareLink(item: url) {
                                    Label("Send", systemImage: "square.and.arrow.up")
                                }
                                .font(.caption)
                            }
                        }

                        Text(video.recordedAt, format: .dateTime.month().day().year().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !video.notes.isEmpty {
                            Text(video.notes)
                                .font(.subheadline)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .onDelete { offsets in
                    for index in offsets {
                        student.videos.removeAll { $0.persistentModelID == sortedVideos[index].persistentModelID }
                    }
                }
            }
        }
        .sheet(item: $selectedVideoForPlayback) { video in
            VideoPlayerSheet(video: video, studentName: student.name)
        }
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
    @State private var recordedAt = Date.now
    @State private var notes = ""
    @State private var showCamera = false
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var pendingVideoURL: URL?
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                DatePicker("Recorded", selection: $recordedAt)
                TextField("Analysis notes", text: $notes, axis: .vertical)
                    .lineLimit(3...8)

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
                            recordedAt: recordedAt,
                            notes: notes,
                            fileURLString: pendingVideoURL?.absoluteString
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
    @Query(sort: \Student.name) private var students: [Student]
    @State private var selectedVideoForPlayback: VideoPlaybackSelection?

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
                                    selectedVideoForPlayback = VideoPlaybackSelection(video: item.video, studentName: item.student.name)
                                } label: {
                                    Image(systemName: "play.circle")
                                }

                                ShareLink(item: url) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Videos")
            .sheet(item: $selectedVideoForPlayback) { selection in
                VideoPlayerSheet(video: selection.video, studentName: selection.studentName)
            }
        }
    }
}

struct VideoPlaybackSelection: Identifiable {
    let video: LessonVideo
    let studentName: String

    var id: PersistentIdentifier {
        video.persistentModelID
    }
}

struct VideoPlayerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let video: LessonVideo
    let studentName: String

    var body: some View {
        NavigationStack {
            Group {
                if let url = video.fileURL {
                    VideoPlayer(player: AVPlayer(url: url))
                        .background(.black)
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
                    Button("Done") { dismiss() }
                }

                if let url = video.fileURL {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: url) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(studentName)
                        .font(.headline)
                    Text(video.recordedAt, format: .dateTime.month().day().year().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !video.notes.isEmpty {
                        Text(video.notes)
                            .font(.subheadline)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.regularMaterial)
            }
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

enum VideoFileStore {
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

    private static func makeDestinationURL(fileExtension: String) throws -> URL {
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = documents.appending(path: "GolfCoachVideos", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "\(UUID().uuidString).\(fileExtension)")
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
