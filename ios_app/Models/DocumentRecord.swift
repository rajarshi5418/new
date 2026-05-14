// Models/DocumentRecord.swift
// SwiftData model representing one analysed document/photo.

import Foundation
import SwiftData

@Model
final class DocumentRecord {
    var id: UUID
    var timestamp: Date
    var photoPath: String        // path to saved JPEG in Documents directory
    var name: String             // extracted from subject / document text
    var department: String
    var fileNo: String
    var sanchikaNo: String
    var rankId: String
    var unit: String
    var subjectHindi: String
    var subjectEnglish: String
    var year: String
    var purpose: String
    var rawAnalysis: String      // full Claude response text

    // Structured section fields
    var summary: String
    var mainSubjects: String
    var environmentContext: String
    var technicalQuality: String
    var notableDetails: String
    var suggestedFollowUp: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        photoPath: String = "",
        name: String = "",
        department: String = "",
        fileNo: String = "",
        sanchikaNo: String = "",
        rankId: String = "",
        unit: String = "",
        subjectHindi: String = "",
        subjectEnglish: String = "",
        year: String = "",
        purpose: String = "",
        rawAnalysis: String = "",
        summary: String = "",
        mainSubjects: String = "",
        environmentContext: String = "",
        technicalQuality: String = "",
        notableDetails: String = "",
        suggestedFollowUp: String = ""
    ) {
        self.id = id
        self.timestamp = timestamp
        self.photoPath = photoPath
        self.name = name
        self.department = department
        self.fileNo = fileNo
        self.sanchikaNo = sanchikaNo
        self.rankId = rankId
        self.unit = unit
        self.subjectHindi = subjectHindi
        self.subjectEnglish = subjectEnglish
        self.year = year
        self.purpose = purpose
        self.rawAnalysis = rawAnalysis
        self.summary = summary
        self.mainSubjects = mainSubjects
        self.environmentContext = environmentContext
        self.technicalQuality = technicalQuality
        self.notableDetails = notableDetails
        self.suggestedFollowUp = suggestedFollowUp
    }

    /// Convenience initialiser that populates from an AnalysisResult.
    convenience init(from result: AnalysisResult, photoPath: String) {
        self.init(
            photoPath: photoPath,
            name: result.name,
            department: result.department,
            fileNo: result.fileNo,
            sanchikaNo: result.sanchikaNo,
            rankId: result.rankId,
            unit: result.unit,
            subjectHindi: result.subjectHindi,
            subjectEnglish: result.subjectEnglish,
            year: result.year,
            purpose: result.purpose,
            rawAnalysis: result.rawText,
            summary: result.summary,
            mainSubjects: result.mainSubjects,
            environmentContext: result.environmentContext,
            technicalQuality: result.technicalQuality,
            notableDetails: result.notableDetails,
            suggestedFollowUp: result.suggestedFollowUp
        )
    }

    /// Formatted timestamp string for display.
    var formattedDate: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: timestamp)
    }

    /// Display name — falls back to date string if name is empty.
    var displayName: String {
        name.isEmpty ? "Document \(formattedDate)" : name
    }

    /// UIImage loaded from photoPath (nil if file missing).
    var thumbnail: UIImage? {
        guard !photoPath.isEmpty else { return nil }
        return UIImage(contentsOfFile: photoPath)
    }
}

// MARK: - UIImage import (needed in Model layer)
import UIKit
