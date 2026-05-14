// Services/ExportService.swift
// Generates XML Spreadsheet (.xls) and CSV exports from DocumentRecord data.

import Foundation

enum ExportError: LocalizedError {
    case writeFailed(Error)
    case noRecords

    var errorDescription: String? {
        switch self {
        case .writeFailed(let e): return "Failed to write export file: \(e.localizedDescription)"
        case .noRecords: return "No records to export."
        }
    }
}

final class ExportService {

    static let shared = ExportService()
    private init() {}

    // MARK: - Column Definitions

    private let columns: [(header: String, keyPath: (DocumentRecord) -> String)] = [
        ("ID",               { $0.id.uuidString }),
        ("Timestamp",        { $0.formattedDate }),
        ("Name",             { $0.name }),
        ("Department",       { $0.department }),
        ("File No.",         { $0.fileNo }),
        ("Sanchika No.",     { $0.sanchikaNo }),
        ("Rank/ID",          { $0.rankId }),
        ("Unit",             { $0.unit }),
        ("Subject (Hindi)",  { $0.subjectHindi }),
        ("Subject (English)",{ $0.subjectEnglish }),
        ("Year",             { $0.year }),
        ("Purpose",          { $0.purpose }),
        ("Summary",          { $0.summary }),
        ("Main Subjects",    { $0.mainSubjects }),
        ("Environment & Context", { $0.environmentContext }),
        ("Technical Quality",    { $0.technicalQuality }),
        ("Notable Details",      { $0.notableDetails }),
        ("Suggested Follow-up",  { $0.suggestedFollowUp }),
        ("Photo Path",       { $0.photoPath }),
        ("Raw Analysis",     { $0.rawAnalysis }),
    ]

    // MARK: - XML Spreadsheet (.xls)

    /// Generates an XML Spreadsheet (Office 2003 XML) file that Excel and
    /// Numbers can open without any ZIP compression — it is plain XML text.
    func generateXLS(records: [DocumentRecord]) throws -> URL {
        guard !records.isEmpty else { throw ExportError.noRecords }

        var xml = """
<?xml version="1.0" encoding="UTF-8"?>
<?mso-application progid="Excel.Sheet"?>
<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"
  xmlns:o="urn:schemas-microsoft-com:office:office"
  xmlns:x="urn:schemas-microsoft-com:office:excel"
  xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet"
  xmlns:html="http://www.w3.org/TR/REC-html40">
  <Styles>
    <Style ss:ID="Default" ss:Name="Normal">
      <Alignment ss:Vertical="Top" ss:WrapText="1"/>
      <Font ss:FontName="Helvetica Neue" ss:Size="11"/>
    </Style>
    <Style ss:ID="Header">
      <Alignment ss:Horizontal="Center" ss:Vertical="Center" ss:WrapText="1"/>
      <Font ss:Bold="1" ss:Color="#FFFFFF" ss:Size="11" ss:FontName="Helvetica Neue"/>
      <Interior ss:Color="#1F3864" ss:Pattern="Solid"/>
    </Style>
    <Style ss:ID="Even">
      <Alignment ss:Vertical="Top" ss:WrapText="1"/>
      <Font ss:FontName="Helvetica Neue" ss:Size="11"/>
      <Interior ss:Color="#DCE6F1" ss:Pattern="Solid"/>
    </Style>
    <Style ss:ID="Odd">
      <Alignment ss:Vertical="Top" ss:WrapText="1"/>
      <Font ss:FontName="Helvetica Neue" ss:Size="11"/>
    </Style>
    <Style ss:ID="MetaLabel">
      <Font ss:Bold="1" ss:FontName="Helvetica Neue" ss:Size="11"/>
    </Style>
  </Styles>
  <Worksheet ss:Name="Document Analysis">
    <Table ss:DefaultRowHeight="60">
"""

        // Header row
        xml += "      <Row ss:Height=\"36\">\n"
        for col in columns {
            xml += "        <Cell ss:StyleID=\"Header\"><Data ss:Type=\"String\">\(xmlEscape(col.header))</Data></Cell>\n"
        }
        xml += "      </Row>\n"

        // Data rows
        for (index, record) in records.enumerated() {
            let styleID = index % 2 == 0 ? "Even" : "Odd"
            xml += "      <Row>\n"
            for col in columns {
                let value = col.keyPath(record)
                xml += "        <Cell ss:StyleID=\"\(styleID)\"><Data ss:Type=\"String\">\(xmlEscape(value))</Data></Cell>\n"
            }
            xml += "      </Row>\n"
        }

        xml += """
    </Table>
    <WorksheetOptions xmlns="urn:schemas-microsoft-com:office:excel">
      <FreezePanes/>
      <FrozenNoSplit/>
      <SplitHorizontal>1</SplitHorizontal>
      <TopRowBottomPane>1</TopRowBottomPane>
      <ActivePane>2</ActivePane>
    </WorksheetOptions>
  </Worksheet>
  <Worksheet ss:Name="Summary">
    <Table>
      <Column ss:Width="140"/>
      <Column ss:Width="300"/>
      <Row>
        <Cell ss:StyleID="MetaLabel"><Data ss:Type="String">Generated</Data></Cell>
        <Cell><Data ss:Type="String">\(xmlEscape(formattedNow()))</Data></Cell>
      </Row>
      <Row>
        <Cell ss:StyleID="MetaLabel"><Data ss:Type="String">Total Records</Data></Cell>
        <Cell><Data ss:Type="Number">\(records.count)</Data></Cell>
      </Row>
      <Row>
        <Cell ss:StyleID="MetaLabel"><Data ss:Type="String">Model</Data></Cell>
        <Cell><Data ss:Type="String">claude-sonnet-4-6</Data></Cell>
      </Row>
      <Row>
        <Cell ss:StyleID="MetaLabel"><Data ss:Type="String">App</Data></Cell>
        <Cell><Data ss:Type="String">CameraClaude iOS</Data></Cell>
      </Row>
    </Table>
  </Worksheet>
</Workbook>
"""

        let fileName = "CameraClaude_\(fileTimestamp()).xls"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try xml.write(to: tempURL, atomically: true, encoding: .utf8)
        } catch {
            throw ExportError.writeFailed(error)
        }
        return tempURL
    }

    /// Generates an XLS for a single record.
    func generateXLS(record: DocumentRecord) throws -> URL {
        return try generateXLS(records: [record])
    }

    // MARK: - CSV Fallback

    func generateCSV(records: [DocumentRecord]) throws -> URL {
        guard !records.isEmpty else { throw ExportError.noRecords }

        var lines: [String] = []

        // Header
        lines.append(columns.map { csvEscape($0.header) }.joined(separator: ","))

        // Data
        for record in records {
            let row = columns.map { csvEscape($0.keyPath(record)) }
            lines.append(row.joined(separator: ","))
        }

        let csv = lines.joined(separator: "\r\n")
        let fileName = "CameraClaude_\(fileTimestamp()).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)
        } catch {
            throw ExportError.writeFailed(error)
        }
        return tempURL
    }

    // MARK: - Helpers

    private func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func csvEscape(_ s: String) -> String {
        let needsQuoting = s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r")
        if needsQuoting {
            let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return s
    }

    private func fileTimestamp() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd_HHmmss"
        return fmt.string(from: Date())
    }

    private func formattedNow() -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .long
        fmt.timeStyle = .medium
        return fmt.string(from: Date())
    }
}
