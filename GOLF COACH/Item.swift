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
    var historyNotes: String
    var focusAreas: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade) var packages: [LessonPackage]
    @Relationship(deleteRule: .cascade) var lessons: [LessonAppointment]
    @Relationship(deleteRule: .cascade) var videos: [LessonVideo]

    init(
        name: String = "New Student",
        phoneNumber: String = "",
        email: String = "",
        historyNotes: String = "",
        focusAreas: String = "",
        createdAt: Date = .now,
        packages: [LessonPackage] = [],
        lessons: [LessonAppointment] = [],
        videos: [LessonVideo] = []
    ) {
        self.name = name
        self.phoneNumber = phoneNumber
        self.email = email
        self.historyNotes = historyNotes
        self.focusAreas = focusAreas
        self.createdAt = createdAt
        self.packages = packages
        self.lessons = lessons
        self.videos = videos
    }

    var activePackage: LessonPackage? {
        packages
            .filter { $0.remainingLessons > 0 }
            .sorted { $0.purchaseDate > $1.purchaseDate }
            .first
    }

    var totalPaid: Decimal {
        packages.reduce(Decimal.zero) { $0 + $1.totalPaid }
    }

    var remainingLessons: Int {
        packages.reduce(0) { $0 + $1.remainingLessons }
    }
}

@Model
final class LessonPackage {
    var packageTypeRawValue: String
    var lessonsPurchased: Int
    var lessonsUsed: Int
    var totalPaid: Decimal
    var purchaseDate: Date

    init(
        packageType: LessonPackageType = .fiveLesson,
        lessonsPurchased: Int = 5,
        lessonsUsed: Int = 0,
        totalPaid: Decimal = 0,
        purchaseDate: Date = .now
    ) {
        self.packageTypeRawValue = packageType.rawValue
        self.lessonsPurchased = lessonsPurchased
        self.lessonsUsed = lessonsUsed
        self.totalPaid = totalPaid
        self.purchaseDate = purchaseDate
    }

    var packageType: LessonPackageType {
        get { LessonPackageType(rawValue: packageTypeRawValue) ?? .custom }
        set { packageTypeRawValue = newValue.rawValue }
    }

    var remainingLessons: Int {
        max(lessonsPurchased - lessonsUsed, 0)
    }

    var amountPerLesson: Decimal {
        guard lessonsPurchased > 0 else { return 0 }
        return totalPaid / Decimal(lessonsPurchased)
    }

    var amountDeducted: Decimal {
        amountPerLesson * Decimal(lessonsUsed)
    }

    var remainingValue: Decimal {
        max(totalPaid - amountDeducted, 0)
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

    init(
        title: String = "Swing Video",
        recordedAt: Date = .now,
        notes: String = "",
        fileURLString: String? = nil
    ) {
        self.title = title
        self.recordedAt = recordedAt
        self.notes = notes
        self.fileURLString = fileURLString
    }

    var fileURL: URL? {
        guard let fileURLString else { return nil }
        return URL(string: fileURLString)
    }
}
