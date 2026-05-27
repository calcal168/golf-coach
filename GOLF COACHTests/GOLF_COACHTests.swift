//
//  GOLF_COACHTests.swift
//  GOLF COACHTests
//
//  Created by Calvin Deng on 2026-05-19.
//

import Foundation
import Testing
@testable import GOLF_COACH

struct GOLF_COACHTests {

    @Test func legacyLessonDeductionsRemainCompatible() {
        let package = LessonPackage(
            packageType: .tenLesson,
            lessonsPurchased: 10,
            lessonsUsed: 2,
            totalPaid: 1_000
        )

        #expect(package.amountDeducted == 200)
        #expect(package.remainingValue == 800)
    }

    @Test func sessionChargesUseRecordedAmounts() {
        let package = LessonPackage(
            packageType: .tenLesson,
            lessonsPurchased: 10,
            lessonsUsed: 2,
            totalPaid: 1_000,
            charges: [
                LessonCharge(durationMinutes: 30, participantCount: 1, amount: 50),
                LessonCharge(durationMinutes: 60, participantCount: 3, amount: 180)
            ]
        )

        #expect(package.amountDeducted == 230)
        #expect(package.remainingValue == 770)
    }

    @Test func accountStatementIncludesChargeHistoryAndRemainingCredit() {
        let firstCharge = LessonCharge(durationMinutes: 30, participantCount: 2, amount: 190)
        let secondCharge = LessonCharge(durationMinutes: 45, participantCount: 3, amount: 280)
        let package = LessonPackage(
            packageType: .fiveLesson,
            lessonsPurchased: 5,
            lessonsUsed: 2,
            totalPaid: 1_000,
            charges: [firstCharge, secondCharge]
        )
        let student = Student(name: "Taylor", packages: [package])

        let message = StudentAccountStatementFormatter.message(
            for: student,
            latestCharge: secondCharge
        )

        #expect(message.contains("Hi Taylor"))
        #expect(message.contains("New charge:"))
        #expect(message.contains("30 min, 2 players"))
        #expect(message.contains("45 min, 3 players"))
        #expect(message.contains("Total charged:"))
        #expect(message.contains("Remaining credit:"))
    }

    @Test func studentLessonSummaryExcludesPrivateCoachJournal() {
        let note = LessonSessionNote(
            lessonFocus: "Putting setup",
            coachNotes: "Maintain shoulder alignment.",
            homework: "Practice ten putts daily.",
            drills: "Gate drill",
            nextLessonGoal: "Distance control",
            privateCoachJournal: "Do not share this observation."
        )

        let summary = StudentLessonSummaryFormatter.summary(for: note, studentName: "Taylor")

        #expect(summary.contains("Taylor"))
        #expect(summary.contains("Putting setup"))
        #expect(summary.contains("Maintain shoulder alignment."))
        #expect(summary.contains("Practice ten putts daily."))
        #expect(summary.contains("Gate drill"))
        #expect(summary.contains("Distance control"))
        #expect(!summary.contains("Do not share this observation."))
    }

    @Test func legacySessionNotesStillPopulateStudentSummary() {
        let note = LessonSessionNote(
            focus: "Grip fundamentals",
            problems: "Alignment drift",
            improvements: "Alignment stick drill",
            generalNotes: "Keep the takeaway smooth."
        )

        let summary = StudentLessonSummaryFormatter.summary(for: note, studentName: "Taylor")

        #expect(summary.contains("Grip fundamentals"))
        #expect(summary.contains("Alignment drift"))
        #expect(summary.contains("Alignment stick drill"))
        #expect(summary.contains("Keep the takeaway smooth."))
    }

    @Test func assignedDrillsAreIncludedInStudentSummary() {
        let drill = Drill(
            title: "Gate Putting",
            category: "Putting",
            purpose: "Improve start line.",
            instructions: "Roll ten balls through two tees.",
            recommendedReps: "3 sets of 10",
            coachTips: "Keep the face square."
        )
        let note = LessonSessionNote(assignedDrills: [drill])

        let summary = StudentLessonSummaryFormatter.summary(for: note, studentName: "Taylor")

        #expect(summary.contains("Gate Putting"))
        #expect(summary.contains("Improve start line."))
        #expect(summary.contains("Roll ten balls through two tees."))
        #expect(summary.contains("3 sets of 10"))
        #expect(summary.contains("Keep the face square."))
    }

}
