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

}
