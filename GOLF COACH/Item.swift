//
//  Item.swift
//  GOLF COACH
//
//  Created by Calvin Deng on 2026-05-19.
//

import Foundation
import SwiftData

enum LessonPackageType: String, CaseIterable, Identifiable, Codable {
    case single = "Single Lesson"
    case fiveLesson = "5-Lesson Package"
    case tenLesson = "10-Lesson Package"
    case custom = "Custom Package"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .single:
            return String(localized: "Single Lesson")
        case .fiveLesson:
            return String(localized: "5-Lesson Package")
        case .tenLesson:
            return String(localized: "10-Lesson Package")
        case .custom:
            return String(localized: "Custom Package")
        }
    }
}

enum PaymentMethod: String, CaseIterable, Identifiable, Codable {
    case creditCard = "Credit Card"
    case debit = "Debit"
    case cash = "Cash"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .creditCard:
            return String(localized: "Credit Card")
        case .debit:
            return String(localized: "Debit")
        case .cash:
            return String(localized: "Cash")
        }
    }
}

enum ReminderLeadTime: String, CaseIterable, Identifiable, Codable {
    case none = "No Reminder"
    case oneDay = "1 Day Before"
    case oneWeek = "1 Week Before"

    var id: String { rawValue }

    var notificationOffset: TimeInterval? {
        switch self {
        case .none:
            return nil
        case .oneDay:
            return 24 * 60 * 60
        case .oneWeek:
            return 7 * 24 * 60 * 60
        }
    }
}

@Model
final class Student {
    var name: String
    var phoneNumber: String
    var email: String
    var birthday: Date?
    var referralPersonName: String?
    // Retained so existing records and older backups remain compatible.
    var age: String?
    var yearsOfExperience: String?
    var handicap: String?
    var golfGoal: String?
    var jobInfo: String?
    var createdAt: Date
    var photoData: Data?

    @Relationship(deleteRule: .cascade) var packages: [LessonPackage]
    @Relationship(deleteRule: .cascade) var lessons: [LessonAppointment]
    @Relationship(deleteRule: .cascade) var videos: [LessonVideo]
    @Relationship(deleteRule: .cascade) var coachAnalysisVideos: [CoachAnalysisVideo]
    @Relationship(deleteRule: .cascade) var sessionNotes: [LessonSessionNote]

    init(
        name: String = "New Student",
        phoneNumber: String = "",
        email: String = "",
        birthday: Date? = nil,
        referralPersonName: String? = nil,
        age: String? = nil,
        yearsOfExperience: String? = nil,
        handicap: String? = nil,
        golfGoal: String? = nil,
        jobInfo: String? = nil,
        createdAt: Date = .now,
        photoData: Data? = nil,
        packages: [LessonPackage] = [],
        lessons: [LessonAppointment] = [],
        videos: [LessonVideo] = [],
        coachAnalysisVideos: [CoachAnalysisVideo] = [],
        sessionNotes: [LessonSessionNote] = []
    ) {
        self.name = name
        self.phoneNumber = phoneNumber
        self.email = email
        self.birthday = birthday
        self.referralPersonName = referralPersonName
        self.age = age
        self.yearsOfExperience = yearsOfExperience
        self.handicap = handicap
        self.golfGoal = golfGoal
        self.jobInfo = jobInfo
        self.createdAt = createdAt
        self.photoData = photoData
        self.packages = packages
        self.lessons = lessons
        self.videos = videos
        self.coachAnalysisVideos = coachAnalysisVideos
        self.sessionNotes = sessionNotes
    }

    var activePackage: LessonPackage? {
        packages
            .filter { $0.remainingValue > 0 }
            .sorted { $0.purchaseDate > $1.purchaseDate }
            .first
    }

    var totalPaid: Decimal {
        packages.reduce(Decimal.zero) { $0 + $1.totalPaid }
    }

    var remainingLessons: Int {
        packages.reduce(0) { $0 + $1.remainingLessons }
    }

    var remainingValue: Decimal {
        packages.reduce(Decimal.zero) { $0 + $1.remainingValue }
    }

    var lessonBalanceTextMessage: String {
        lessonBalanceTextMessage(remainingLessons: remainingLessons)
    }

    func lessonBalanceTextMessage(remainingLessons: Int) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let greeting = trimmedName.isEmpty ? "Hi" : "Hi \(trimmedName)"

        switch remainingLessons {
        case 0:
            return "\(greeting), you currently have no golf lessons remaining."
        case 1:
            return "\(greeting), you currently have 1 golf lesson remaining."
        default:
            return "\(greeting), you currently have \(remainingLessons) golf lessons remaining."
        }
    }
}

@Model
final class CoachAnalysisVideo {
    var title: String
    var recordedAt: Date
    var fileURLString: String?
    var notes: String
    var lessonDate: Date?

    init(
        title: String = "Coach Analysis",
        recordedAt: Date = .now,
        fileURLString: String? = nil,
        notes: String = "",
        lessonDate: Date? = nil
    ) {
        self.title = title
        self.recordedAt = recordedAt
        self.fileURLString = fileURLString
        self.notes = notes
        self.lessonDate = lessonDate
    }

    var fileURL: URL? {
        guard let fileURLString else { return nil }

        if let absoluteURL = URL(string: fileURLString),
           absoluteURL.isFileURL,
           FileManager.default.fileExists(atPath: absoluteURL.path) {
            return absoluteURL
        }

        let fileName: String
        if let absoluteURL = URL(string: fileURLString), absoluteURL.isFileURL {
            fileName = absoluteURL.lastPathComponent
        } else {
            fileName = fileURLString
        }

        guard let videosDirectory = Self.videosDirectory else { return nil }
        let resolvedURL = videosDirectory.appending(path: fileName)
        return FileManager.default.fileExists(atPath: resolvedURL.path) ? resolvedURL : nil
    }

    private static var videosDirectory: URL? {
        try? FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appending(path: "GolfCoachVideos", directoryHint: .isDirectory)
    }
}

@Model
final class LessonPackage {
    var packageTypeRawValue: String
    var lessonsPurchased: Int
    var lessonsUsed: Int
    var totalPaid: Decimal
    var purchaseDate: Date
    var paymentMethodRawValue: String?
    @Relationship(deleteRule: .cascade) var charges: [LessonCharge]

    init(
        packageType: LessonPackageType = .fiveLesson,
        lessonsPurchased: Int = 5,
        lessonsUsed: Int = 0,
        totalPaid: Decimal = 0,
        purchaseDate: Date = .now,
        paymentMethod: PaymentMethod? = nil,
        charges: [LessonCharge] = []
    ) {
        self.packageTypeRawValue = packageType.rawValue
        self.lessonsPurchased = lessonsPurchased
        self.lessonsUsed = lessonsUsed
        self.totalPaid = totalPaid
        self.purchaseDate = purchaseDate
        self.paymentMethodRawValue = paymentMethod?.rawValue
        self.charges = charges
    }

    var packageType: LessonPackageType {
        get { LessonPackageType(rawValue: packageTypeRawValue) ?? .custom }
        set { packageTypeRawValue = newValue.rawValue }
    }

    var paymentMethod: PaymentMethod? {
        get { paymentMethodRawValue.flatMap(PaymentMethod.init(rawValue:)) }
        set { paymentMethodRawValue = newValue?.rawValue }
    }

    var remainingLessons: Int {
        max(lessonsPurchased - lessonsUsed, 0)
    }

    var amountPerLesson: Decimal {
        guard lessonsPurchased > 0 else { return 0 }
        return totalPaid / Decimal(lessonsPurchased)
    }

    var amountDeducted: Decimal {
        let legacyLessonCount = max(lessonsUsed - charges.count, 0)
        let legacyAmount = amountPerLesson * Decimal(legacyLessonCount)
        let recordedAmount = charges.reduce(Decimal.zero) { $0 + $1.amount }
        return legacyAmount + recordedAmount
    }

    var remainingValue: Decimal {
        max(totalPaid - amountDeducted, 0)
    }
}

@Model
final class LessonCharge {
    var chargedAt: Date
    var durationMinutes: Int
    var participantCount: Int
    var amount: Decimal
    var notes: String

    init(
        chargedAt: Date = .now,
        durationMinutes: Int = 60,
        participantCount: Int = 1,
        amount: Decimal = 0,
        notes: String = ""
    ) {
        self.chargedAt = chargedAt
        self.durationMinutes = durationMinutes
        self.participantCount = participantCount
        self.amount = amount
        self.notes = notes
    }
}

@Model
final class LessonAppointment {
    var title: String
    var scheduledAt: Date
    var durationMinutes: Int
    var location: String
    var notes: String
    var reminderLeadTimeRawValue: String
    var isCompleted: Bool
    var notificationIdentifier: String?
    var calendarEventIdentifier: String?

    init(
        title: String = "Golf Lesson",
        scheduledAt: Date = .now,
        durationMinutes: Int = 60,
        location: String = "",
        notes: String = "",
        reminderLeadTime: ReminderLeadTime = .oneDay,
        isCompleted: Bool = false,
        notificationIdentifier: String? = nil,
        calendarEventIdentifier: String? = nil
    ) {
        self.title = title
        self.scheduledAt = scheduledAt
        self.durationMinutes = durationMinutes
        self.location = location
        self.notes = notes
        self.reminderLeadTimeRawValue = reminderLeadTime.rawValue
        self.isCompleted = isCompleted
        self.notificationIdentifier = notificationIdentifier
        self.calendarEventIdentifier = calendarEventIdentifier
    }

    var reminderLeadTime: ReminderLeadTime {
        get { ReminderLeadTime(rawValue: reminderLeadTimeRawValue) ?? .none }
        set { reminderLeadTimeRawValue = newValue.rawValue }
    }

    var endDate: Date {
        scheduledAt.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }
}

@Model
final class LessonVideo {
    var title: String
    var recordedAt: Date
    var notes: String
    var fileURLString: String?
    var lessonDate: Date?
    var focusNotes: String?
    var problemNotes: String?
    var comparisonNotes: String?
    var analysisDrawingData: String?
    var trimStartSeconds: Double?
    var trimEndSeconds: Double?

    init(
        title: String = "Swing Video",
        recordedAt: Date = .now,
        notes: String = "",
        fileURLString: String? = nil,
        lessonDate: Date? = nil,
        focusNotes: String? = nil,
        problemNotes: String? = nil,
        comparisonNotes: String? = nil,
        analysisDrawingData: String? = nil,
        trimStartSeconds: Double? = nil,
        trimEndSeconds: Double? = nil
    ) {
        self.title = title
        self.recordedAt = recordedAt
        self.notes = notes
        self.fileURLString = fileURLString
        self.lessonDate = lessonDate
        self.focusNotes = focusNotes
        self.problemNotes = problemNotes
        self.comparisonNotes = comparisonNotes
        self.analysisDrawingData = analysisDrawingData
        self.trimStartSeconds = trimStartSeconds
        self.trimEndSeconds = trimEndSeconds
    }

    var fileURL: URL? {
        guard let fileURLString else { return nil }

        if let absoluteURL = URL(string: fileURLString),
           absoluteURL.isFileURL,
           FileManager.default.fileExists(atPath: absoluteURL.path) {
            return absoluteURL
        }

        let fileName: String
        if let absoluteURL = URL(string: fileURLString), absoluteURL.isFileURL {
            fileName = absoluteURL.lastPathComponent
        } else {
            fileName = fileURLString
        }

        guard let videosDirectory = Self.videosDirectory else { return nil }
        let resolvedURL = videosDirectory.appending(path: fileName)
        return FileManager.default.fileExists(atPath: resolvedURL.path) ? resolvedURL : nil
    }

    private static var videosDirectory: URL? {
        try? FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appending(path: "GolfCoachVideos", directoryHint: .isDirectory)
    }
}

@Model
final class LessonSessionNote {
    var sessionDate: Date
    var focus: String
    var problems: String
    var improvements: String
    var generalNotes: String

    init(
        sessionDate: Date = .now,
        focus: String = "",
        problems: String = "",
        improvements: String = "",
        generalNotes: String = ""
    ) {
        self.sessionDate = sessionDate
        self.focus = focus
        self.problems = problems
        self.improvements = improvements
        self.generalNotes = generalNotes
    }
}
