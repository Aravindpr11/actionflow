import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/services/report_service.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:flutter/material.dart';

/// Professional multi-sheet Excel generator for ActionFlow using MIT-licensed `excel_plus`.
///
/// Produces an executive-ready `.xlsx` workbook with:
/// 1. Dashboard: Formula-driven KPIs, active filter summary, 4 native Excel charts
/// 2. Action Register: 22 columns, real Excel dates, native AutoFilter, native Excel Table
/// 3. Action Lifecycle: Complete audit trail of real milestones (Created, Assigned, Updates, Closed)
/// 4. Progress History: Detailed updates across filtered actions with separate Update Date vs Submitted At
/// 5. Comments & Reviews: Worker notes, safety remarks, manager reviews, and closure verification
/// 6. Lists & Reference: Lookup categories and validation options
class ExcelExportService {
  ExcelExportService._();
  static final ExcelExportService instance = ExcelExportService._();

  // Color constants for Excel styling (ARGB)
  static final ExcelColor headerBgColor = ExcelColor.fromHexString(
    'FF1E293B',
  ); // Slate 800
  static final ExcelColor subHeaderBgColor = ExcelColor.fromHexString(
    'FF334155',
  ); // Slate 700
  static final ExcelColor sectionHeaderBgColor = ExcelColor.fromHexString(
    'FF0F766E',
  ); // Teal 700
  static final ExcelColor kpiHeaderBgColor = ExcelColor.fromHexString(
    'FF1E3A8A',
  ); // Blue 900
  static const ExcelColor whiteColor = ExcelColor.white;
  static const ExcelColor blackColor = ExcelColor.black;

  /// Helper to convert date strings to real [DateCellValue]
  CellValue _parseDate(dynamic raw) {
    if (raw == null) return TextCellValue('');
    final str = raw.toString().trim();
    if (str.isEmpty) return TextCellValue('');
    final dbDate = ActionRecord.formatDateForDb(str);
    final dt = DateTime.tryParse(dbDate);
    if (dt != null) {
      return DateCellValue(year: dt.year, month: dt.month, day: dt.day);
    }
    return TextCellValue(str);
  }

  /// Helper to convert timestamps to real [DateTimeCellValue]
  CellValue _parseDateTime(dynamic raw) {
    if (raw == null) return TextCellValue('');
    if (raw is DateTime) {
      return DateTimeCellValue.fromDateTime(raw.toLocal());
    }
    final str = raw.toString().trim();
    if (str.isEmpty) return TextCellValue('');
    final dt = DateTime.tryParse(str);
    if (dt != null) {
      return DateTimeCellValue.fromDateTime(dt.toLocal());
    }
    return TextCellValue(str);
  }

  /// Applies standard header styling to a row in a sheet
  void _styleHeaderRow(
    Sheet sheet,
    int rowIndex,
    int columnCount, {
    ExcelColor? bgColor,
  }) {
    final style = CellStyle(
      bold: true,
      fontColorHex: whiteColor,
      backgroundColorHex: bgColor ?? headerBgColor,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    for (int col = 0; col < columnCount; col++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIndex),
      );
      cell.cellStyle = style;
    }
  }

  /// Builds a 6-sheet executive Excel workbook based strictly on the filtered action records.
  Excel buildExportWorkbook({
    required List<ActionRecord> filteredActions,
    required String userName,
    required String userRole,
    required String organizationName,
    required Map<String, String> activeFilters,
  }) {
    final excel = Excel.createExcel();

    const dashboardSheetName = 'Dashboard';
    const registerSheetName = 'Action Register';
    const lifecycleSheetName = 'Action Lifecycle';
    const historySheetName = 'Progress History';
    const commentsSheetName = 'Comments & Reviews';
    const listsSheetName = 'Lists & Reference';

    // Rename default Sheet1 to Dashboard and make it the default active sheet
    excel.rename('Sheet1', dashboardSheetName);
    excel.setDefaultSheet(dashboardSheetName);

    final Sheet dashSheet = excel[dashboardSheetName];
    final Sheet regSheet = excel[registerSheetName];
    final Sheet lifecycleSheet = excel[lifecycleSheetName];
    final Sheet historySheet = excel[historySheetName];
    final Sheet commentsSheet = excel[commentsSheetName];
    final Sheet listsSheet = excel[listsSheetName];

    final int actionCount = filteredActions.length;
    final int regMaxRow = actionCount > 0 ? actionCount + 1 : 2;

    // =========================================================================
    // SHEET 2: Action Register (Populated first so formulas can reference it)
    // =========================================================================
    final registerHeaders = [
      'Action ID', // A
      'Subject', // B
      'Description', // C
      'Action Required', // D
      'Category', // E
      'Priority', // F
      'Status', // G
      'Progress %', // H
      'Assigned To', // I
      'Assigned By', // J
      'Division', // K
      'Department', // L
      'Site', // M
      'Section', // N
      'Date Raised', // O
      'Start Date', // P
      'Due / Target Date', // Q
      'Follow-Up Date', // R
      'Latest Update Date', // S
      'Latest Work Update', // T
      'Closed Date', // U
      'Closed By', // V
      'Closure Verification Comment', // W
    ];

    for (int i = 0; i < registerHeaders.length; i++) {
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = TextCellValue(
        registerHeaders[i],
      );
    }
    _styleHeaderRow(regSheet, 0, registerHeaders.length);

    for (int r = 0; r < actionCount; r++) {
      final a = filteredActions[r];
      final rowIdx = r + 1;

      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx))
          .value = TextCellValue(
        a.displayId,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIdx))
          .value = TextCellValue(
        a.subject,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIdx))
          .value = TextCellValue(
        a.description,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIdx))
          .value = TextCellValue(
        a.actionRequired,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIdx))
          .value = TextCellValue(
        a.category,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIdx))
          .value = TextCellValue(
        a.priority,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIdx))
          .value = TextCellValue(
        a.status,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIdx))
          .value = IntCellValue(
        a.percentComplete,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: rowIdx))
          .value = TextCellValue(
        a.assignedTo,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: rowIdx))
          .value = TextCellValue(
        a.assignedBy,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: rowIdx))
          .value = TextCellValue(
        a.division,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: rowIdx))
          .value = TextCellValue(
        a.department,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: rowIdx))
          .value = TextCellValue(
        a.site,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: rowIdx))
          .value = TextCellValue(
        a.section,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: rowIdx))
          .value = _parseDate(
        a.dateRaised,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 15, rowIndex: rowIdx))
          .value = _parseDate(
        a.startDate,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 16, rowIndex: rowIdx))
          .value = _parseDate(
        a.targetDate,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 17, rowIndex: rowIdx))
          .value = _parseDate(
        a.nextFollowUpDate,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 18, rowIndex: rowIdx))
          .value = _parseDate(
        a.latestUpdateDate,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 19, rowIndex: rowIdx))
          .value = TextCellValue(
        a.latestWorkUpdate,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 20, rowIndex: rowIdx))
          .value = _parseDate(
        a.closeDate,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 21, rowIndex: rowIdx))
          .value = TextCellValue(
        a.closedByName ?? a.verifiedBy,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 22, rowIndex: rowIdx))
          .value = TextCellValue(
        a.closureComment,
      );
    }

    // Freeze header row on Action Register
    regSheet.freezePanes(rows: 1, columns: 0);

    // Native Excel Table on Action Register (automatically includes native table AutoFilter)
    if (actionCount > 0) {
      final regToCell = CellIndex.indexByColumnRow(
        columnIndex: registerHeaders.length - 1,
        rowIndex: actionCount,
      );
      regSheet.addTable(
        ExcelTable(
          name: 'ActionRegisterTable',
          from: CellIndex.indexByString('A1'),
          to: regToCell,
          style: TableStyle.medium9,
        ),
      );
    }

    // Set practical column widths
    regSheet.setColumnWidth(0, 16.0); // ID
    regSheet.setColumnWidth(1, 30.0); // Subject
    regSheet.setColumnWidth(2, 35.0); // Description
    regSheet.setColumnWidth(3, 30.0); // Action Required
    regSheet.setColumnWidth(4, 18.0); // Category
    regSheet.setColumnWidth(5, 14.0); // Priority
    regSheet.setColumnWidth(6, 16.0); // Status
    regSheet.setColumnWidth(7, 14.0); // Progress %
    regSheet.setColumnWidth(8, 22.0); // Assigned To
    regSheet.setColumnWidth(9, 22.0); // Assigned By
    regSheet.setColumnWidth(10, 20.0); // Division
    regSheet.setColumnWidth(11, 22.0); // Department
    regSheet.setColumnWidth(14, 16.0); // Date Raised
    regSheet.setColumnWidth(15, 18.0); // Due Date
    regSheet.setColumnWidth(19, 16.0); // Closed Date
    regSheet.setColumnWidth(21, 35.0); // Closure Comment
    regSheet.setColumnWidth(15, 16.0); // Start Date
    regSheet.setColumnWidth(16, 18.0); // Due Date
    regSheet.setColumnWidth(17, 18.0); // Follow-Up Date
    regSheet.setColumnWidth(20, 16.0); // Closed Date
    regSheet.setColumnWidth(22, 35.0); // Closure Comment

    // =========================================================================
    // SHEET 1: Dashboard (Formulas, KPIs, Filters, 4 Native Charts)
    // =========================================================================
    // Header Banner
    dashSheet.cell(CellIndex.indexByString('A1')).value = TextCellValue(
      'ACTIONFLOW EXECUTIVE DASHBOARD',
    );
    dashSheet.cell(CellIndex.indexByString('A1')).cellStyle = CellStyle(
      bold: true,
      fontSize: 16,
      fontColorHex: whiteColor,
      backgroundColorHex: headerBgColor,
    );

    dashSheet.cell(CellIndex.indexByString('A2')).value = TextCellValue(
      'Organization:',
    );
    dashSheet.cell(CellIndex.indexByString('B2')).value = TextCellValue(
      organizationName,
    );
    dashSheet.cell(CellIndex.indexByString('A3')).value = TextCellValue(
      'Generated By:',
    );
    dashSheet.cell(CellIndex.indexByString('B3')).value = TextCellValue(
      '$userName ($userRole)',
    );
    dashSheet.cell(CellIndex.indexByString('A4')).value = TextCellValue(
      'Generated At:',
    );
    dashSheet.cell(CellIndex.indexByString('B4')).value = TextCellValue(
      DateTime.now().toLocal().toString().split('.').first,
    );
    dashSheet.cell(CellIndex.indexByString('A5')).value = TextCellValue(
      'Export Scope:',
    );
    dashSheet.cell(CellIndex.indexByString('B5')).value = TextCellValue(
      activeFilters.isEmpty
          ? 'All Actions (No filters applied)'
          : activeFilters.entries
                .map((e) => '${e.key}: ${e.value}')
                .join(' | '),
    );

    for (int r = 1; r <= 4; r++) {
      dashSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
          .cellStyle = CellStyle(
        bold: true,
        fontColorHex: whiteColor,
        backgroundColorHex: subHeaderBgColor,
      );
    }

    // Active Filters Card
    dashSheet.cell(CellIndex.indexByString('A7')).value = TextCellValue(
      'ACTIVE FILTERS CONFIGURATION',
    );
    dashSheet.cell(CellIndex.indexByString('B7')).value = TextCellValue(
      'FILTER VALUE',
    );
    _styleHeaderRow(dashSheet, 6, 2, bgColor: subHeaderBgColor);

    int filterRow = 7;
    if (activeFilters.isEmpty) {
      dashSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: filterRow))
          .value = TextCellValue(
        'None',
      );
      dashSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: filterRow))
          .value = TextCellValue(
        'Entire dataset exported',
      );
      filterRow++;
    } else {
      activeFilters.forEach((key, val) {
        dashSheet
            .cell(
              CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: filterRow),
            )
            .value = TextCellValue(
          key,
        );
        dashSheet
            .cell(
              CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: filterRow),
            )
            .value = TextCellValue(
          val,
        );
        filterRow++;
      });
    }

    // Formula-driven KPIs
    final kpiStartRow = filterRow + 1;
    dashSheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: kpiStartRow))
        .value = TextCellValue(
      'KEY PERFORMANCE INDICATORS (FORMULAS)',
    );
    dashSheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: kpiStartRow))
        .value = TextCellValue(
      'FORMULA DRIVEN VALUE',
    );
    _styleHeaderRow(dashSheet, kpiStartRow, 2, bgColor: kpiHeaderBgColor);

    final kpis = [
      ('Total Actions Exported', "COUNTA('Action Register'!A2:A$regMaxRow)"),
      ('Open Actions', "COUNTIF('Action Register'!G2:G$regMaxRow, \"Open\")"),
      (
        'In Progress Actions',
        "COUNTIF('Action Register'!G2:G$regMaxRow, \"In Progress\")",
      ),
      (
        'Closed Actions',
        "COUNTIF('Action Register'!G2:G$regMaxRow, \"Closed\")",
      ),
      (
        'Overdue Actions',
        "COUNTIF('Action Register'!G2:G$regMaxRow, \"Overdue\")",
      ),
      (
        'Average Completion %',
        "IFERROR(AVERAGE('Action Register'!H2:H$regMaxRow), 0)",
      ),
    ];

    for (int k = 0; k < kpis.length; k++) {
      final rIdx = kpiStartRow + 1 + k;
      dashSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rIdx))
          .value = TextCellValue(
        kpis[k].$1,
      );
      dashSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rIdx))
          .value = FormulaCellValue(
        kpis[k].$2,
      );
    }

    // -------------------------------------------------------------------------
    // Summary Data Tables on Dashboard (To drive the 4 Native Excel Charts)
    // -------------------------------------------------------------------------
    // Table 1: Status Distribution (Columns D & E, Rows 1-6)
    dashSheet.cell(CellIndex.indexByString('D1')).value = TextCellValue(
      'Status',
    );
    dashSheet.cell(CellIndex.indexByString('E1')).value = TextCellValue(
      'Count',
    );
    _styleHeaderRow(dashSheet, 0, 2, bgColor: sectionHeaderBgColor);
    dashSheet.cell(CellIndex.indexByString('D1')).cellStyle = CellStyle(
      bold: true,
      fontColorHex: whiteColor,
      backgroundColorHex: sectionHeaderBgColor,
    );
    dashSheet.cell(CellIndex.indexByString('E1')).cellStyle = CellStyle(
      bold: true,
      fontColorHex: whiteColor,
      backgroundColorHex: sectionHeaderBgColor,
    );

    final statusList = ['Open', 'In Progress', 'Closed', 'Overdue'];
    for (int s = 0; s < statusList.length; s++) {
      final r = s + 1;
      dashSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r))
          .value = TextCellValue(
        statusList[s],
      );
      dashSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r))
          .value = FormulaCellValue(
        "COUNTIF('Action Register'!G2:G$regMaxRow, \"${statusList[s]}\")",
      );
    }

    // Table 2: Priority Distribution (Columns G & H, Rows 1-4)
    dashSheet.cell(CellIndex.indexByString('G1')).value = TextCellValue(
      'Priority',
    );
    dashSheet.cell(CellIndex.indexByString('H1')).value = TextCellValue(
      'Count',
    );
    dashSheet.cell(CellIndex.indexByString('G1')).cellStyle = CellStyle(
      bold: true,
      fontColorHex: whiteColor,
      backgroundColorHex: sectionHeaderBgColor,
    );
    dashSheet.cell(CellIndex.indexByString('H1')).cellStyle = CellStyle(
      bold: true,
      fontColorHex: whiteColor,
      backgroundColorHex: sectionHeaderBgColor,
    );

    final priorityList = ['High', 'Medium', 'Low'];
    for (int p = 0; p < priorityList.length; p++) {
      final r = p + 1;
      dashSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r))
          .value = TextCellValue(
        priorityList[p],
      );
      dashSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: r))
          .value = FormulaCellValue(
        "COUNTIF('Action Register'!F2:F$regMaxRow, \"${priorityList[p]}\")",
      );
    }

    // Table 3: Department Distribution (Columns J & K, Rows 1-5)
    dashSheet.cell(CellIndex.indexByString('J1')).value = TextCellValue(
      'Department',
    );
    dashSheet.cell(CellIndex.indexByString('K1')).value = TextCellValue(
      'Count',
    );
    dashSheet.cell(CellIndex.indexByString('J1')).cellStyle = CellStyle(
      bold: true,
      fontColorHex: whiteColor,
      backgroundColorHex: sectionHeaderBgColor,
    );
    dashSheet.cell(CellIndex.indexByString('K1')).cellStyle = CellStyle(
      bold: true,
      fontColorHex: whiteColor,
      backgroundColorHex: sectionHeaderBgColor,
    );

    final deptSet = filteredActions
        .map((a) => a.department.trim())
        .where((d) => d.isNotEmpty)
        .toSet()
        .toList();
    if (deptSet.isEmpty) deptSet.add('General');
    final deptCount = deptSet.length > 6 ? 6 : deptSet.length;
    for (int d = 0; d < deptCount; d++) {
      final r = d + 1;
      dashSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: r))
          .value = TextCellValue(
        deptSet[d],
      );
      dashSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: r))
          .value = FormulaCellValue(
        "COUNTIF('Action Register'!L2:L$regMaxRow, \"${deptSet[d]}\")",
      );
    }
    final deptEndRow = deptCount + 1;

    // Table 4: Completion Milestones (Columns M & N, Rows 1-5)
    dashSheet.cell(CellIndex.indexByString('M1')).value = TextCellValue(
      'Completion Stage',
    );
    dashSheet.cell(CellIndex.indexByString('N1')).value = TextCellValue(
      'Count',
    );
    dashSheet.cell(CellIndex.indexByString('M1')).cellStyle = CellStyle(
      bold: true,
      fontColorHex: whiteColor,
      backgroundColorHex: sectionHeaderBgColor,
    );
    dashSheet.cell(CellIndex.indexByString('N1')).cellStyle = CellStyle(
      bold: true,
      fontColorHex: whiteColor,
      backgroundColorHex: sectionHeaderBgColor,
    );

    final completionStages = [
      ('0% Not Started', "COUNTIF('Action Register'!H2:H$regMaxRow, 0)"),
      (
        '1-49% Progress',
        "COUNTIFS('Action Register'!H2:H$regMaxRow, \">0\", 'Action Register'!H2:H$regMaxRow, \"<50\")",
      ),
      (
        '50-99% Progress',
        "COUNTIFS('Action Register'!H2:H$regMaxRow, \">=50\", 'Action Register'!H2:H$regMaxRow, \"<100\")",
      ),
      ('100% Completed', "COUNTIF('Action Register'!H2:H$regMaxRow, 100)"),
    ];

    for (int c = 0; c < completionStages.length; c++) {
      final r = c + 1;
      dashSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: r))
          .value = TextCellValue(
        completionStages[c].$1,
      );
      dashSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: r))
          .value = FormulaCellValue(
        completionStages[c].$2,
      );
    }

    // -------------------------------------------------------------------------
    // 4 Native Excel Charts Anchored on Dashboard
    // -------------------------------------------------------------------------
    final chartBaseRow = kpiStartRow + kpis.length + 2;

    // Chart 1: Status Column Chart
    dashSheet.addChart(
      Chart.column(
        anchor: CellIndex.indexByColumnRow(
          columnIndex: 0,
          rowIndex: chartBaseRow,
        ),
        title: 'Action Status Breakdown',
        categories: 'Dashboard!D2:D5',
        series: [ChartSeries(name: 'Actions', values: 'Dashboard!E2:E5')],
        width: 440,
        height: 280,
      ),
    );

    // Chart 2: Priority Pie Chart
    dashSheet.addChart(
      Chart.pie(
        anchor: CellIndex.indexByColumnRow(
          columnIndex: 6,
          rowIndex: chartBaseRow,
        ),
        title: 'Actions by Priority',
        categories: 'Dashboard!G2:G4',
        series: ChartSeries(name: 'Priority', values: 'Dashboard!H2:H4'),
        width: 440,
        height: 280,
      ),
    );

    // Chart 3: Department Bar Chart
    dashSheet.addChart(
      Chart.bar(
        anchor: CellIndex.indexByColumnRow(
          columnIndex: 0,
          rowIndex: chartBaseRow + 16,
        ),
        title: 'Actions by Department',
        categories: 'Dashboard!J2:J$deptEndRow',
        series: [
          ChartSeries(name: 'Department', values: 'Dashboard!K2:K$deptEndRow'),
        ],
        width: 440,
        height: 280,
      ),
    );

    // Chart 4: Completion Doughnut Chart
    dashSheet.addChart(
      Chart.doughnut(
        anchor: CellIndex.indexByColumnRow(
          columnIndex: 6,
          rowIndex: chartBaseRow + 16,
        ),
        title: 'Action Completion Milestones',
        categories: 'Dashboard!M2:M5',
        series: ChartSeries(name: 'Completion', values: 'Dashboard!N2:N5'),
        width: 440,
        height: 280,
      ),
    );

    dashSheet.setColumnWidth(0, 28.0);
    dashSheet.setColumnWidth(1, 35.0);
    dashSheet.setColumnWidth(3, 16.0);
    dashSheet.setColumnWidth(4, 12.0);
    dashSheet.setColumnWidth(6, 16.0);
    dashSheet.setColumnWidth(7, 12.0);
    dashSheet.setColumnWidth(9, 22.0);
    dashSheet.setColumnWidth(10, 12.0);
    dashSheet.setColumnWidth(12, 22.0);
    dashSheet.setColumnWidth(13, 12.0);

    // =========================================================================
    // SHEET 3: Action Lifecycle (One row per real milestone)
    // =========================================================================
    final lifecycleHeaders = [
      'Action ID',
      'Subject',
      'Lifecycle Stage',
      'Event Date',
      'Submitted At',
      'Performed By',
      'Status',
      'Progress %',
      'Milestone Notes / Remarks',
    ];

    for (int i = 0; i < lifecycleHeaders.length; i++) {
      lifecycleSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = TextCellValue(
        lifecycleHeaders[i],
      );
    }
    _styleHeaderRow(lifecycleSheet, 0, lifecycleHeaders.length);

    int lRow = 1;
    for (final a in filteredActions) {
      // 1. Created milestone
      lifecycleSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: lRow))
          .value = TextCellValue(
        a.displayId,
      );
      lifecycleSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: lRow))
          .value = TextCellValue(
        a.subject,
      );
      lifecycleSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: lRow))
          .value = TextCellValue(
        'Created',
      );
      lifecycleSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: lRow))
          .value = _parseDate(
        a.dateRaised,
      );
      lifecycleSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: lRow))
          .value = _parseDateTime(
        a.dateRaised,
      );
      lifecycleSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: lRow))
          .value = TextCellValue(
        a.assignedBy.isNotEmpty ? a.assignedBy : 'Creator',
      );
      lifecycleSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: lRow))
          .value = TextCellValue(
        'Open',
      );
      lifecycleSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: lRow))
          .value = IntCellValue(
        0,
      );
      lifecycleSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: lRow))
          .value = TextCellValue(
        a.description.isNotEmpty ? a.description : 'Action logged',
      );
      lRow++;

      // 2. Assigned milestone
      if (a.assignedTo.isNotEmpty && a.assignedTo != 'Unassigned') {
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: lRow))
            .value = TextCellValue(
          a.displayId,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: lRow))
            .value = TextCellValue(
          a.subject,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: lRow))
            .value = TextCellValue(
          'Assigned',
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: lRow))
            .value = _parseDate(
          a.dateRaised,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: lRow))
            .value = _parseDateTime(
          a.dateRaised,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: lRow))
            .value = TextCellValue(
          a.assignedBy,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: lRow))
            .value = TextCellValue(
          a.status,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: lRow))
            .value = IntCellValue(
          0,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: lRow))
            .value = TextCellValue(
          'Assigned to ${a.assignedTo}',
        );
        lRow++;
      }

      // 3. Follow-Up Checkpoints
      for (final f in a.followUps) {
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: lRow))
            .value = TextCellValue(
          a.displayId,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: lRow))
            .value = TextCellValue(
          a.subject,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: lRow))
            .value = TextCellValue(
          f.isCompleted ? 'Follow-Up Completed' : 'Follow-Up Checkpoint',
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: lRow))
            .value = _parseDate(
          f.followUpDate,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: lRow))
            .value = _parseDateTime(
          f.completedAt?.toIso8601String() ?? f.createdAt?.toIso8601String(),
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: lRow))
            .value = TextCellValue(
          f.createdByName.isNotEmpty ? f.createdByName : a.assignedBy,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: lRow))
            .value = TextCellValue(
          f.status,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: lRow))
            .value = IntCellValue(
          f.actualProgress ?? a.percentComplete,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: lRow))
            .value = TextCellValue(
          f.notes.isNotEmpty
              ? 'Notes: ${f.notes}'
              : 'Scheduled review checkpoint',
        );
        lRow++;
      }

      // 4. Contributors Added
      for (final c in a.contributors) {
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: lRow))
            .value = TextCellValue(
          a.displayId,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: lRow))
            .value = TextCellValue(
          a.subject,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: lRow))
            .value = TextCellValue(
          'Contributor Added',
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: lRow))
            .value = _parseDate(
          ActionRecord.formatDateForUi(c.createdAt),
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: lRow))
            .value = _parseDateTime(
          c.createdAt?.toIso8601String(),
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: lRow))
            .value = TextCellValue(
          c.addedByName.isNotEmpty ? c.addedByName : a.assignedTo,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: lRow))
            .value = TextCellValue(
          a.status,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: lRow))
            .value = IntCellValue(
          a.percentComplete,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: lRow))
            .value = TextCellValue(
          'Added ${c.profileName} as contributor${c.notes.isNotEmpty ? ' (${c.notes})' : ''}',
        );
        lRow++;
      }

      // 5. Progress Updates
      final sortedUpdates = List<ActionProgressUpdate>.from(a.progressUpdates)
        ..sort((x, y) {
          final xDate =
              x.createdAt ??
              DateTime.tryParse(ActionRecord.formatDateForDb(x.updateDate)) ??
              DateTime(1970);
          final yDate =
              y.createdAt ??
              DateTime.tryParse(ActionRecord.formatDateForDb(y.updateDate)) ??
              DateTime(1970);
          return xDate.compareTo(yDate);
        });

      for (final upd in sortedUpdates) {
        final isHundred = upd.progress >= 100;
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: lRow))
            .value = TextCellValue(
          a.displayId,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: lRow))
            .value = TextCellValue(
          a.subject,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: lRow))
            .value = TextCellValue(
          isHundred ? '100% Completion Milestone' : 'Progress Update',
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: lRow))
            .value = _parseDate(
          upd.updateDate,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: lRow))
            .value = _parseDateTime(
          upd.createdAt,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: lRow))
            .value = TextCellValue(
          upd.updatedByName,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: lRow))
            .value = TextCellValue(
          upd.status,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: lRow))
            .value = IntCellValue(
          upd.progress,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: lRow))
            .value = TextCellValue(
          upd.contributionValue > 0
              ? '${upd.comments} (Contribution: +${upd.contributionValue}%)'
              : upd.comments,
        );
        lRow++;
      }

      // 4. Closed milestone
      if (a.isClosed || a.closeDate.isNotEmpty) {
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: lRow))
            .value = TextCellValue(
          a.displayId,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: lRow))
            .value = TextCellValue(
          a.subject,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: lRow))
            .value = TextCellValue(
          'Closed & Verified',
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: lRow))
            .value = _parseDate(
          a.closeDate,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: lRow))
            .value = _parseDateTime(
          a.closedAt?.toIso8601String() ?? a.closeDate,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: lRow))
            .value = TextCellValue(
          a.closedByName ?? a.verifiedBy,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: lRow))
            .value = TextCellValue(
          'Closed',
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: lRow))
            .value = IntCellValue(
          a.percentComplete,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: lRow))
            .value = TextCellValue(
          a.closureComment.isNotEmpty
              ? a.closureComment
              : 'Action formally closed and verified',
        );
        lRow++;
      }
    }

    lifecycleSheet.freezePanes(rows: 1, columns: 0);
    if (lRow > 1) {
      final lToCell = CellIndex.indexByColumnRow(
        columnIndex: lifecycleHeaders.length - 1,
        rowIndex: lRow - 1,
      );
      lifecycleSheet.addTable(
        ExcelTable(
          name: 'ActionLifecycleTable',
          from: CellIndex.indexByString('A1'),
          to: lToCell,
          style: TableStyle.medium2,
        ),
      );
    }
    lifecycleSheet.setColumnWidth(0, 16.0);
    lifecycleSheet.setColumnWidth(1, 28.0);
    lifecycleSheet.setColumnWidth(2, 25.0);
    lifecycleSheet.setColumnWidth(3, 16.0);
    lifecycleSheet.setColumnWidth(4, 22.0);
    lifecycleSheet.setColumnWidth(5, 22.0);
    lifecycleSheet.setColumnWidth(8, 35.0);

    // =========================================================================
    // SHEET 4: Progress History (Updates across filtered actions)
    // =========================================================================
    final historyHeaders = [
      'Action ID',
      'Subject',
      'Update Date',
      'Submitted At',
      'Updated By',
      'Progress %',
      'Status',
      'Work Update / Comments',
    ];

    for (int i = 0; i < historyHeaders.length; i++) {
      historySheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = TextCellValue(
        historyHeaders[i],
      );
    }
    _styleHeaderRow(historySheet, 0, historyHeaders.length);

    int hRow = 1;
    for (final a in filteredActions) {
      if (a.progressUpdates.isNotEmpty) {
        for (final upd in a.progressUpdates) {
          historySheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: hRow))
              .value = TextCellValue(
            a.displayId,
          );
          historySheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: hRow))
              .value = TextCellValue(
            a.subject,
          );
          historySheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: hRow))
              .value = _parseDate(
            upd.updateDate,
          );
          historySheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: hRow))
              .value = _parseDateTime(
            upd.createdAt,
          );
          historySheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: hRow))
              .value = TextCellValue(
            upd.updatedByName,
          );
          historySheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: hRow))
              .value = IntCellValue(
            upd.progress,
          );
          historySheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: hRow))
              .value = TextCellValue(
            upd.status,
          );
          historySheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: hRow))
              .value = TextCellValue(
            upd.comments,
          );
          hRow++;
        }
      } else if (a.history.isNotEmpty) {
        for (final h in a.history) {
          historySheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: hRow))
              .value = TextCellValue(
            a.displayId,
          );
          historySheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: hRow))
              .value = TextCellValue(
            a.subject,
          );
          historySheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: hRow))
              .value = TextCellValue(
            '',
          );
          historySheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: hRow))
              .value = TextCellValue(
            '',
          );
          historySheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: hRow))
              .value = TextCellValue(
            '',
          );
          historySheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: hRow))
              .value = IntCellValue(
            a.percentComplete,
          );
          historySheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: hRow))
              .value = TextCellValue(
            a.status,
          );
          historySheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: hRow))
              .value = TextCellValue(
            h,
          );
          hRow++;
        }
      }
    }

    if (hRow == 1) {
      historySheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1))
          .value = TextCellValue(
        'No progress updates recorded for the filtered actions.',
      );
      hRow++;
    }

    historySheet.freezePanes(rows: 1, columns: 0);
    if (hRow > 2) {
      final hToCell = CellIndex.indexByColumnRow(
        columnIndex: historyHeaders.length - 1,
        rowIndex: hRow - 1,
      );
      historySheet.addTable(
        ExcelTable(
          name: 'ProgressHistoryTable',
          from: CellIndex.indexByString('A1'),
          to: hToCell,
          style: TableStyle.light9,
        ),
      );
    }
    historySheet.setColumnWidth(0, 16.0);
    historySheet.setColumnWidth(1, 28.0);
    historySheet.setColumnWidth(2, 16.0);
    historySheet.setColumnWidth(3, 22.0);
    historySheet.setColumnWidth(4, 22.0);
    historySheet.setColumnWidth(7, 35.0);

    // =========================================================================
    // SHEET 5: Comments & Review History
    // =========================================================================
    final commentHeaders = [
      'Action ID',
      'Subject',
      'Comment Type',
      'Date / Timestamp',
      'Author',
      'Remarks / Verification Details',
    ];

    for (int i = 0; i < commentHeaders.length; i++) {
      commentsSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = TextCellValue(
        commentHeaders[i],
      );
    }
    _styleHeaderRow(commentsSheet, 0, commentHeaders.length);

    int cRow = 1;
    for (final a in filteredActions) {
      if (a.closureComment.isNotEmpty) {
        commentsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: cRow))
            .value = TextCellValue(
          a.displayId,
        );
        commentsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: cRow))
            .value = TextCellValue(
          a.subject,
        );
        commentsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: cRow))
            .value = TextCellValue(
          'Closure Verification',
        );
        commentsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: cRow))
            .value = _parseDate(
          a.closeDate,
        );
        commentsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: cRow))
            .value = TextCellValue(
          a.closedByName ?? a.verifiedBy,
        );
        commentsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: cRow))
            .value = TextCellValue(
          a.closureComment,
        );
        cRow++;
      }

      if (a.managerMessage.isNotEmpty) {
        commentsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: cRow))
            .value = TextCellValue(
          a.displayId,
        );
        commentsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: cRow))
            .value = TextCellValue(
          a.subject,
        );
        commentsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: cRow))
            .value = TextCellValue(
          'Manager Feedback',
        );
        commentsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: cRow))
            .value = TextCellValue(
          '',
        );
        commentsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: cRow))
            .value = TextCellValue(
          a.assignedBy,
        );
        commentsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: cRow))
            .value = TextCellValue(
          a.managerMessage,
        );
        cRow++;
      }

      for (final upd in a.progressUpdates) {
        if (upd.comments.isNotEmpty) {
          commentsSheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: cRow))
              .value = TextCellValue(
            a.displayId,
          );
          commentsSheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: cRow))
              .value = TextCellValue(
            a.subject,
          );
          commentsSheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: cRow))
              .value = TextCellValue(
            'Work Update Remark',
          );
          commentsSheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: cRow))
              .value = _parseDate(
            upd.updateDate,
          );
          commentsSheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: cRow))
              .value = TextCellValue(
            upd.updatedByName,
          );
          commentsSheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: cRow))
              .value = TextCellValue(
            upd.comments,
          );
          cRow++;
        }
      }
    }

    if (cRow == 1) {
      commentsSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1))
          .value = TextCellValue(
        'No comments recorded for the filtered actions.',
      );
      cRow++;
    }

    commentsSheet.freezePanes(rows: 1, columns: 0);
    if (cRow > 2) {
      final cToCell = CellIndex.indexByColumnRow(
        columnIndex: commentHeaders.length - 1,
        rowIndex: cRow - 1,
      );
      commentsSheet.addTable(
        ExcelTable(
          name: 'CommentsReviewTable',
          from: CellIndex.indexByString('A1'),
          to: cToCell,
          style: TableStyle.light9,
        ),
      );
    }
    commentsSheet.setColumnWidth(0, 16.0);
    commentsSheet.setColumnWidth(1, 28.0);
    commentsSheet.setColumnWidth(2, 22.0);
    commentsSheet.setColumnWidth(3, 18.0);
    commentsSheet.setColumnWidth(4, 22.0);
    commentsSheet.setColumnWidth(5, 40.0);

    // =========================================================================
    // SHEET 6: Lists & Reference
    // =========================================================================
    final listHeaders = [
      'Categories',
      'Priorities',
      'Statuses',
      'Divisions',
      'Departments',
    ];

    for (int i = 0; i < listHeaders.length; i++) {
      listsSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = TextCellValue(
        listHeaders[i],
      );
    }
    _styleHeaderRow(listsSheet, 0, listHeaders.length);

    final standardCategories = [
      'HSE',
      'Safety',
      'Environment',
      'Quality',
      'Maintenance',
      'Compliance',
      'Operations',
      'Inspection',
      'Audit',
    ];
    final standardPriorities = ['Critical', 'High', 'Medium', 'Low'];
    final standardStatuses = [
      'Open',
      'In Progress',
      'Closed',
      'Overdue',
      'Pending Review',
      'Ready for Review',
    ];
    final divisions = filteredActions
        .map((a) => a.division.trim())
        .where((d) => d.isNotEmpty)
        .toSet()
        .toList();
    if (divisions.isEmpty) divisions.addAll(['Operations', 'Corporate', 'HSE']);

    final maxListRows = [
      standardCategories.length,
      standardPriorities.length,
      standardStatuses.length,
      divisions.length,
      deptSet.length,
    ].reduce((a, b) => a > b ? a : b);

    for (int i = 0; i < maxListRows; i++) {
      final rIdx = i + 1;
      if (i < standardCategories.length) {
        listsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rIdx))
            .value = TextCellValue(
          standardCategories[i],
        );
      }
      if (i < standardPriorities.length) {
        listsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rIdx))
            .value = TextCellValue(
          standardPriorities[i],
        );
      }
      if (i < standardStatuses.length) {
        listsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rIdx))
            .value = TextCellValue(
          standardStatuses[i],
        );
      }
      if (i < divisions.length) {
        listsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rIdx))
            .value = TextCellValue(
          divisions[i],
        );
      }
      if (i < deptSet.length) {
        listsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rIdx))
            .value = TextCellValue(
          deptSet[i],
        );
      }
    }
    listsSheet.freezePanes(rows: 1, columns: 0);

    // =========================================================================
    // Evaluate and cache formulas for immediate display
    // =========================================================================
    excel.recalculate();

    return excel;
  }

  /// Exports the filtered actions to Excel and triggers file download.
  /// If [filteredActions] is empty, displays a user-facing notification and cancels export.
  Future<bool> exportFilteredActions({
    required BuildContext context,
    required List<ActionRecord> filteredActions,
    required String userName,
    required String userRole,
    required String organizationName,
    required Map<String, String> activeFilters,
    String? fileName,
  }) async {
    if (filteredActions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No actions match the selected filters.'),
          backgroundColor: Color(0xFFEA580C),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }

    try {
      final excel = buildExportWorkbook(
        filteredActions: filteredActions,
        userName: userName,
        userRole: userRole,
        organizationName: organizationName,
        activeFilters: activeFilters,
      );

      final dateStr = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final outFileName = fileName ?? 'ActionFlow_Actions_$dateStr.xlsx';

      // Native browser download on web via excel_plus SavingHelper, or local file save
      excel.save(fileName: outFileName);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Exported ${filteredActions.length} action${filteredActions.length == 1 ? '' : 's'} to Excel successfully.',
          ),
          backgroundColor: const Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('[ExcelExportService] Export error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to export Excel file: $e'),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }
  }

  // ===========================================================================
  // MANAGER REPORTS EXECUTIVE DASHBOARD WORKBOOK GENERATOR
  // ===========================================================================

  /// Builds a 15-sheet executive Manager Reports Excel workbook featuring:
  /// - Sheet 1: Dashboard with executive banner, metadata, filter summary, 7 KPI cards, and 12 native Excel charts
  /// - Sheet 2: Action Register with 24 columns, ExcelTable, AutoFilter, real dates & percentages
  /// - Sheet 3: Action Lifecycle (milestones)
  /// - Sheet 4: Progress History
  /// - Sheet 5: Comments & Reviews
  /// - Sheets 6-13: 8 Analytics sheets feeding Dashboard charts
  /// - Sheet 14: Lists & Reference
  Excel buildReportWorkbook({
    required List<ActionRecord> filteredActions,
    required String userName,
    required String userRole,
    required String organizationName,
    required Map<String, String> activeFilters,
  }) {
    final excel = Excel.createExcel();

    const dashboardSheetName = 'Dashboard';
    const registerSheetName = 'Action Register';
    const lifecycleSheetName = 'Action Lifecycle';
    const historySheetName = 'Progress History';
    const commentsSheetName = 'Comments & Reviews';
    const statusSheetName = 'Status Analysis';
    const progressSheetName = 'Progress Analysis';
    const prioritySheetName = 'Priority Analysis';
    const deptSheetName = 'Department Analysis';
    const divSheetName = 'Division Analysis';
    const secSheetName = 'Section Analysis';
    const siteSheetName = 'Site Analysis';
    const assigneeSheetName = 'Assignee Analysis';
    const timelineSheetName = 'Timeline Analysis';
    const listsSheetName = 'Lists & Reference';

    // Rename default Sheet1 to Dashboard and set as active default
    excel.rename('Sheet1', dashboardSheetName);
    excel.setDefaultSheet(dashboardSheetName);

    final Sheet dashSheet = excel[dashboardSheetName];
    final Sheet regSheet = excel[registerSheetName];
    final Sheet lifecycleSheet = excel[lifecycleSheetName];
    final Sheet historySheet = excel[historySheetName];
    final Sheet commentsSheet = excel[commentsSheetName];
    final Sheet statusSheet = excel[statusSheetName];
    final Sheet progressSheet = excel[progressSheetName];
    final Sheet prioritySheet = excel[prioritySheetName];
    final Sheet deptSheet = excel[deptSheetName];
    final Sheet divSheet = excel[divSheetName];
    final Sheet secSheet = excel[secSheetName];
    final Sheet siteSheet = excel[siteSheetName];
    final Sheet assigneeSheet = excel[assigneeSheetName];
    final Sheet timelineSheet = excel[timelineSheetName];
    final Sheet listsSheet = excel[listsSheetName];

    final agg = ReportService.compute(filteredActions);
    final int actionCount = filteredActions.length;
    final int regMaxRow = actionCount > 0 ? actionCount + 1 : 2;

    // 1. Populate Action Register (Sheet 2) with 24 columns & ExcelTable
    _populateReportActionRegister(regSheet, filteredActions);

    // 2. Populate Analytics supporting data sheets (Sheets 6-14)
    final deptCount = _populateReportDeptAnalysis(
      deptSheet,
      filteredActions,
      regMaxRow,
    );
    final divCount = _populateReportDivAnalysis(
      divSheet,
      filteredActions,
      regMaxRow,
    );
    final secCount = _populateReportSecAnalysis(
      secSheet,
      filteredActions,
      regMaxRow,
    );
    final siteCount = _populateReportSiteAnalysis(
      siteSheet,
      filteredActions,
      regMaxRow,
    );
    final assCount = _populateReportAssigneeAnalysis(
      assigneeSheet,
      filteredActions,
      agg,
    );
    _populateReportStatusAnalysis(statusSheet, agg, regMaxRow);
    _populateReportProgressAnalysis(progressSheet, agg, regMaxRow);
    _populateReportPriorityAnalysis(prioritySheet, agg, regMaxRow);
    _populateReportTimelineAnalysis(timelineSheet, agg);

    // 3. Populate Dashboard (Sheet 1) with Header, Metadata, Filter Summary, 7 KPIs, and 12 Charts
    _populateReportDashboard(
      dashSheet: dashSheet,
      agg: agg,
      actionCount: actionCount,
      regMaxRow: regMaxRow,
      userName: userName,
      userRole: userRole,
      organizationName: organizationName,
      activeFilters: activeFilters,
      deptEndRow: deptCount + 1,
      divEndRow: divCount + 1,
      secEndRow: secCount + 1,
      siteEndRow: siteCount + 1,
      assEndRow: assCount + 1,
    );

    // 4. Populate Audit & Reference Sheets (Sheets 3, 4, 5, 15)
    _populateReportLifecycleSheet(lifecycleSheet, filteredActions);
    _populateReportProgressHistorySheet(historySheet, filteredActions);
    _populateReportCommentsSheet(commentsSheet, filteredActions);
    _populateReportListsSheet(listsSheet, filteredActions);

    // Recalculate all formulas to ensure cached values are embedded
    excel.recalculate();

    return excel;
  }

  /// Exports the filtered actions to a professional Manager Reports Excel workbook and triggers file download.
  Future<bool> exportReportExcel({
    required BuildContext context,
    required List<ActionRecord> filteredActions,
    required String userName,
    required String userRole,
    required String organizationName,
    required Map<String, String> activeFilters,
    String? fileName,
  }) async {
    if (filteredActions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No actions match the selected report filters.'),
          backgroundColor: Color(0xFFEA580C),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }

    try {
      final excel = buildReportWorkbook(
        filteredActions: filteredActions,
        userName: userName,
        userRole: userRole,
        organizationName: organizationName,
        activeFilters: activeFilters,
      );

      final dateStr = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final outFileName = fileName ?? 'ActionFlow_Manager_Report_$dateStr.xlsx';

      excel.save(fileName: outFileName);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Exported ${filteredActions.length} action${filteredActions.length == 1 ? '' : 's'} to Manager Report Excel successfully.',
          ),
          backgroundColor: const Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('[ExcelExportService] Report Export error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to export Excel report: $e'),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Action Register (24 Columns with real Table & AutoFilter)
  // ---------------------------------------------------------------------------
  void _populateReportActionRegister(
    Sheet regSheet,
    List<ActionRecord> filteredActions,
  ) {
    final registerHeaders = [
      '#', // 0: A
      'Action ID', // 1: B
      'Subject', // 2: C
      'Description', // 3: D
      'Action Required / Instruction', // 4: E
      'Category / Section', // 5: F
      'Department', // 6: G
      'Division', // 7: H
      'Site', // 8: I
      'Priority', // 9: J
      'Status', // 10: K
      'Progress %', // 11: L
      'Assigned To', // 12: M
      'Assigned By', // 13: N
      'External Recipient', // 14: O
      'External Email', // 15: P
      'Raised Date', // 16: Q
      'Start Date', // 17: R
      'Follow-Up Date', // 18: S
      'Target/Due Date', // 19: T
      'Closed Date', // 20: U
      'Days Left / Overdue', // 21: V
      'Created By', // 22: W
      'Last Updated', // 23: X
    ];

    for (int i = 0; i < registerHeaders.length; i++) {
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = TextCellValue(
        registerHeaders[i],
      );
    }
    _styleHeaderRow(regSheet, 0, registerHeaders.length);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (int r = 0; r < filteredActions.length; r++) {
      final a = filteredActions[r];
      final rowIdx = r + 1;

      String daysLeftStr = '';
      if (a.isClosed) {
        daysLeftStr = 'Closed';
      } else if (a.targetDate.isNotEmpty) {
        final dt = ReportService.parseDate(a.targetDate);
        if (dt != null) {
          final diff = dt.difference(today).inDays;
          if (diff < 0) {
            daysLeftStr = '${diff.abs()} days overdue';
          } else if (diff == 0) {
            daysLeftStr = 'Due today';
          } else {
            daysLeftStr = '$diff days left';
          }
        }
      }

      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx))
          .value = IntCellValue(
        r + 1,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIdx))
          .value = TextCellValue(
        a.displayId,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIdx))
          .value = TextCellValue(
        a.subject,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIdx))
          .value = TextCellValue(
        a.description,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIdx))
          .value = TextCellValue(
        a.actionRequired,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIdx))
          .value = TextCellValue(
        a.section.isNotEmpty ? a.section : a.category,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIdx))
          .value = TextCellValue(
        a.department,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIdx))
          .value = TextCellValue(
        a.division,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: rowIdx))
          .value = TextCellValue(
        a.site,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: rowIdx))
          .value = TextCellValue(
        a.priority,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: rowIdx))
          .value = TextCellValue(
        a.status,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: rowIdx))
          .value = IntCellValue(
        a.percentComplete,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: rowIdx))
          .value = TextCellValue(
        a.isExternalRecipient
            ? (a.externalRecipientName ?? 'External')
            : a.assignedTo,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: rowIdx))
          .value = TextCellValue(
        a.assignedBy,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: rowIdx))
          .value = TextCellValue(
        a.isExternalRecipient ? (a.externalRecipientName ?? 'Yes') : 'No',
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 15, rowIndex: rowIdx))
          .value = TextCellValue(
        a.externalRecipientEmail ?? '',
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 16, rowIndex: rowIdx))
          .value = _parseDate(
        a.dateRaised,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 17, rowIndex: rowIdx))
          .value = _parseDate(
        a.startDate,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 18, rowIndex: rowIdx))
          .value = _parseDate(
        a.nextFollowUpDate,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 19, rowIndex: rowIdx))
          .value = _parseDate(
        a.targetDate,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 20, rowIndex: rowIdx))
          .value = _parseDate(
        a.closeDate,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 21, rowIndex: rowIdx))
          .value = TextCellValue(
        daysLeftStr,
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 22, rowIndex: rowIdx))
          .value = TextCellValue(
        a.assignedBy.isNotEmpty ? a.assignedBy : 'Creator',
      );
      regSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 23, rowIndex: rowIdx))
          .value = _parseDate(
        a.latestUpdateDate,
      );
    }

    regSheet.freezePanes(rows: 1, columns: 0);

    if (filteredActions.isNotEmpty) {
      regSheet.addTable(
        ExcelTable(
          name: 'ReportActionRegisterTable',
          from: CellIndex.indexByString('A1'),
          to: CellIndex.indexByColumnRow(
            columnIndex: registerHeaders.length - 1,
            rowIndex: filteredActions.length,
          ),
          style: TableStyle.medium9,
        ),
      );
    }

    // Set appropriate column widths
    regSheet.setColumnWidth(0, 6.0); // #
    regSheet.setColumnWidth(1, 16.0); // ID
    regSheet.setColumnWidth(2, 30.0); // Subject
    regSheet.setColumnWidth(3, 35.0); // Description
    regSheet.setColumnWidth(4, 30.0); // Instruction
    regSheet.setColumnWidth(5, 18.0); // Category / Section
    regSheet.setColumnWidth(6, 22.0); // Department
    regSheet.setColumnWidth(7, 20.0); // Division
    regSheet.setColumnWidth(8, 18.0); // Site
    regSheet.setColumnWidth(9, 14.0); // Priority
    regSheet.setColumnWidth(10, 16.0); // Status
    regSheet.setColumnWidth(11, 14.0); // Progress %
    regSheet.setColumnWidth(12, 24.0); // Assigned To
    regSheet.setColumnWidth(13, 22.0); // Assigned By
    regSheet.setColumnWidth(14, 20.0); // External Recipient
    regSheet.setColumnWidth(15, 25.0); // External Email
    regSheet.setColumnWidth(16, 16.0); // Raised Date
    regSheet.setColumnWidth(17, 16.0); // Start Date
    regSheet.setColumnWidth(18, 18.0); // Follow-Up Date
    regSheet.setColumnWidth(19, 18.0); // Target Date
    regSheet.setColumnWidth(20, 16.0); // Closed Date
    regSheet.setColumnWidth(21, 18.0); // Days Left
    regSheet.setColumnWidth(22, 20.0); // Created By
    regSheet.setColumnWidth(23, 16.0); // Last Updated
  }

  // ---------------------------------------------------------------------------
  // Dashboard Sheet (Executive Header, Metadata, Filters, 7 KPIs, 12 Charts)
  // ---------------------------------------------------------------------------
  void _populateReportDashboard({
    required Sheet dashSheet,
    required ReportAggregates agg,
    required int actionCount,
    required int regMaxRow,
    required String userName,
    required String userRole,
    required String organizationName,
    required Map<String, String> activeFilters,
    required int deptEndRow,
    required int divEndRow,
    required int secEndRow,
    required int siteEndRow,
    required int assEndRow,
  }) {
    // Top Banner
    dashSheet.cell(CellIndex.indexByString('A1')).value = TextCellValue(
      'ACTIONFLOW',
    );
    dashSheet.cell(CellIndex.indexByString('A1')).cellStyle = CellStyle(
      bold: true,
      fontSize: 18,
      fontColorHex: whiteColor,
      backgroundColorHex: ExcelColor.fromHexString('FF0F172A'),
    );

    dashSheet.cell(CellIndex.indexByString('A2')).value = TextCellValue(
      'Manager Reports & Analytics — Executive Action Management Insights',
    );
    dashSheet.cell(CellIndex.indexByString('A2')).cellStyle = CellStyle(
      bold: true,
      fontSize: 12,
      fontColorHex: whiteColor,
      backgroundColorHex: headerBgColor,
    );

    // Metadata Block (Col A & B, Rows 4-7)
    final metaItems = [
      ('Organization:', organizationName),
      ('Generated By:', '$userName ($userRole)'),
      ('Generated At:', DateTime.now().toLocal().toString().split('.').first),
      (
        'Report Period:',
        activeFilters['Date Range'] ?? activeFilters['Date'] ?? 'All Time',
      ),
    ];

    for (int i = 0; i < metaItems.length; i++) {
      final r = 3 + i;
      dashSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
          .value = TextCellValue(
        metaItems[i].$1,
      );
      dashSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
          .cellStyle = CellStyle(
        bold: true,
        fontColorHex: whiteColor,
        backgroundColorHex: subHeaderBgColor,
      );
      dashSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r))
          .value = TextCellValue(
        metaItems[i].$2,
      );
    }

    // Filter Summary Block (Col D-H, Rows 4-8)
    dashSheet.cell(CellIndex.indexByString('D3')).value = TextCellValue(
      'REPORT FILTERS APPLIED',
    );
    dashSheet.cell(CellIndex.indexByString('D3')).cellStyle = CellStyle(
      bold: true,
      fontSize: 11,
      fontColorHex: whiteColor,
      backgroundColorHex: sectionHeaderBgColor,
    );

    final filterPairs = [
      (
        'Date Field:',
        activeFilters['Date Field'] ?? 'All',
        'Date Range:',
        activeFilters['Date Range'] ?? activeFilters['Date'] ?? 'All',
      ),
      (
        'Status:',
        activeFilters['Status'] ?? 'All',
        'Priority:',
        activeFilters['Priority'] ?? 'All',
      ),
      (
        'Department:',
        activeFilters['Department'] ?? 'All',
        'Division:',
        activeFilters['Division'] ?? 'All',
      ),
      (
        'Section:',
        activeFilters['Section'] ?? 'All',
        'Site:',
        activeFilters['Site'] ?? 'All',
      ),
    ];

    for (int i = 0; i < filterPairs.length; i++) {
      final r = 3 + i;
      dashSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r))
          .value = TextCellValue(
        filterPairs[i].$1,
      );
      dashSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r))
          .cellStyle = CellStyle(
        bold: true,
      );
      dashSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r))
          .value = TextCellValue(
        filterPairs[i].$2,
      );

      dashSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r))
          .value = TextCellValue(
        filterPairs[i].$3,
      );
      dashSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r))
          .cellStyle = CellStyle(
        bold: true,
      );
      dashSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r))
          .value = TextCellValue(
        filterPairs[i].$4,
      );
    }

    // Row 8: Assignee filter
    dashSheet.cell(CellIndex.indexByString('D7')).value = TextCellValue(
      'Assignee:',
    );
    dashSheet.cell(CellIndex.indexByString('D7')).cellStyle = CellStyle(
      bold: true,
    );
    dashSheet.cell(CellIndex.indexByString('E7')).value = TextCellValue(
      activeFilters['Assignee'] ?? activeFilters['Person'] ?? 'All',
    );

    // -------------------------------------------------------------------------
    // 7 KPI Cards (Rows 10-12, Columns A to N)
    // -------------------------------------------------------------------------
    final kpis = [
      (
        'TOTAL ACTIONS',
        "COUNTA('Action Register'!B2:B$regMaxRow)",
        '$actionCount',
        ExcelColor.fromHexString('FF1E3A8A'), // Blue 900
        0,
      ),
      (
        'OPEN ACTIONS',
        "COUNTIF('Action Register'!K2:K$regMaxRow, \"Open\")",
        '${agg.open}',
        ExcelColor.fromHexString('FF15803D'), // Green 700
        2,
      ),
      (
        'IN PROGRESS',
        "COUNTIF('Action Register'!K2:K$regMaxRow, \"In Progress\")",
        '${agg.byStatus['In Progress'] ?? 0}',
        ExcelColor.fromHexString('FFB45309'), // Amber 700
        4,
      ),
      (
        'OVERDUE',
        "COUNTIF('Action Register'!K2:K$regMaxRow, \"Overdue\")",
        '${agg.overdue}',
        ExcelColor.fromHexString('FFB91C1C'), // Red 700
        6,
      ),
      (
        'READY FOR REVIEW',
        "COUNTIF('Action Register'!K2:K$regMaxRow, \"Ready for Review\")",
        '${agg.pendingReview}',
        ExcelColor.fromHexString('FF6D28D9'), // Purple 700
        8,
      ),
      (
        'CLOSED ACTIONS',
        "COUNTIF('Action Register'!K2:K$regMaxRow, \"Closed\")",
        '${agg.closed}',
        ExcelColor.fromHexString('FF047857'), // Emerald 700
        10,
      ),
      (
        'AVG PROGRESS',
        "IFERROR(AVERAGE('Action Register'!L2:L$regMaxRow), 0)",
        '${agg.avgCompletionPct.round()}%',
        ExcelColor.fromHexString('FF4338CA'), // Indigo 700
        12,
      ),
    ];

    for (final k in kpis) {
      final col = k.$5;
      // Header row
      dashSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 9))
          .value = TextCellValue(
        k.$1,
      );
      dashSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 9))
          .cellStyle = CellStyle(
        bold: true,
        fontColorHex: whiteColor,
        backgroundColorHex: k.$4,
      );
      // Value row
      dashSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 10))
          .value = FormulaCellValue(
        k.$2,
        cachedValue: k.$3,
      );
      dashSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 10))
          .cellStyle = CellStyle(
        bold: true,
        fontSize: 16,
      );
    }

    // -------------------------------------------------------------------------
    // 12 Native Excel Charts on the Dashboard Sheet
    // -------------------------------------------------------------------------

    // Chart 1: Action Status Distribution (Column)
    dashSheet.addChart(
      Chart.column(
        anchor: CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 16),
        title: 'Action Status Distribution',
        categories: "'Status Analysis'!A2:A6",
        series: [
          ChartSeries(
            name: 'Actions',
            values: "'Status Analysis'!B2:B6",
            color: ExcelColor.fromHexString('FF1565C0'),
          ),
        ],
        width: 480,
        height: 280,
      ),
    );

    // Chart 2: Progress Distribution (Column)
    dashSheet.addChart(
      Chart.column(
        anchor: CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: 16),
        title: 'Action Progress Distribution',
        categories: "'Progress Analysis'!A2:A6",
        series: [
          ChartSeries(
            name: 'Actions',
            values: "'Progress Analysis'!B2:B6",
            color: ExcelColor.fromHexString('FF0F766E'),
          ),
        ],
        width: 480,
        height: 280,
      ),
    );

    // Chart 3: Actions by Priority (Pie)
    dashSheet.addChart(
      Chart.pie(
        anchor: CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 32),
        title: 'Actions by Priority',
        categories: "'Priority Analysis'!A2:A5",
        series: ChartSeries(
          name: 'Priority',
          values: "'Priority Analysis'!B2:B5",
          pointColors: [
            ExcelColor.fromHexString('FFDC2626'), // Critical
            ExcelColor.fromHexString('FFEA580C'), // High
            ExcelColor.fromHexString('FF0284C7'), // Medium
            ExcelColor.fromHexString('FF16A34A'), // Low
          ],
        ),
        width: 480,
        height: 280,
      ),
    );

    // Chart 4: Actions by Department (Bar)
    dashSheet.addChart(
      Chart.bar(
        anchor: CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: 32),
        title: 'Actions by Department',
        categories: "'Department Analysis'!A2:A$deptEndRow",
        series: [
          ChartSeries(
            name: 'Department',
            values: "'Department Analysis'!B2:B$deptEndRow",
            color: ExcelColor.fromHexString('FF1E3A8A'),
          ),
        ],
        width: 480,
        height: 280,
      ),
    );

    // Chart 5: Actions by Division (Bar)
    dashSheet.addChart(
      Chart.bar(
        anchor: CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 48),
        title: 'Actions by Division',
        categories: "'Division Analysis'!A2:A$divEndRow",
        series: [
          ChartSeries(
            name: 'Division',
            values: "'Division Analysis'!B2:B$divEndRow",
            color: ExcelColor.fromHexString('FF334155'),
          ),
        ],
        width: 480,
        height: 280,
      ),
    );

    // Chart 6: Actions by Section (Bar)
    dashSheet.addChart(
      Chart.bar(
        anchor: CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: 48),
        title: 'Actions by Section',
        categories: "'Section Analysis'!A2:A$secEndRow",
        series: [
          ChartSeries(
            name: 'Section',
            values: "'Section Analysis'!B2:B$secEndRow",
            color: ExcelColor.fromHexString('FF0D9488'),
          ),
        ],
        width: 480,
        height: 280,
      ),
    );

    // Chart 7: Actions by Site (Bar)
    dashSheet.addChart(
      Chart.bar(
        anchor: CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 64),
        title: 'Actions by Site',
        categories: "'Site Analysis'!A2:A$siteEndRow",
        series: [
          ChartSeries(
            name: 'Site',
            values: "'Site Analysis'!B2:B$siteEndRow",
            color: ExcelColor.fromHexString('FF2563EB'),
          ),
        ],
        width: 480,
        height: 280,
      ),
    );

    // Chart 8: Top Assignees (Bar)
    dashSheet.addChart(
      Chart.bar(
        anchor: CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: 64),
        title: 'Top Assignees',
        categories: "'Assignee Analysis'!A2:A$assEndRow",
        series: [
          ChartSeries(
            name: 'Actions',
            values: "'Assignee Analysis'!B2:B$assEndRow",
            color: ExcelColor.fromHexString('FF4F46E5'),
          ),
        ],
        width: 480,
        height: 280,
      ),
    );

    // Chart 9: Actions Raised Over Time (Line)
    dashSheet.addChart(
      Chart.line(
        anchor: CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 80),
        title: 'Actions Raised Over Time',
        categories: "'Timeline Analysis'!A2:A13",
        series: [
          ChartSeries(
            name: 'Raised',
            values: "'Timeline Analysis'!B2:B13",
            color: ExcelColor.fromHexString('FF1565C0'),
          ),
        ],
        width: 480,
        height: 280,
      ),
    );

    // Chart 10: Actions Completed/Closed Over Time (Line)
    dashSheet.addChart(
      Chart.line(
        anchor: CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: 80),
        title: 'Actions Completed / Closed Over Time',
        categories: "'Timeline Analysis'!A2:A13",
        series: [
          ChartSeries(
            name: 'Completed',
            values: "'Timeline Analysis'!C2:C13",
            color: ExcelColor.fromHexString('FF16A34A'),
          ),
        ],
        width: 480,
        height: 280,
      ),
    );

    // Chart 11: Overdue Actions Over Time (Line)
    dashSheet.addChart(
      Chart.line(
        anchor: CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 96),
        title: 'Overdue Actions Over Time',
        categories: "'Timeline Analysis'!A2:A13",
        series: [
          ChartSeries(
            name: 'Overdue',
            values: "'Timeline Analysis'!D2:D13",
            color: ExcelColor.fromHexString('FFEA580C'),
          ),
        ],
        width: 480,
        height: 280,
      ),
    );

    // Chart 12: Follow-Up Activity Over Time (Line)
    dashSheet.addChart(
      Chart.line(
        anchor: CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: 96),
        title: 'Follow-Up Activity Over Time',
        categories: "'Timeline Analysis'!A2:A13",
        series: [
          ChartSeries(
            name: 'Follow-Ups',
            values: "'Timeline Analysis'!E2:E13",
            color: ExcelColor.fromHexString('FF7C3AED'),
          ),
        ],
        width: 480,
        height: 280,
      ),
    );

    // Column widths for Dashboard
    dashSheet.setColumnWidth(0, 22.0);
    dashSheet.setColumnWidth(1, 24.0);
    dashSheet.setColumnWidth(2, 18.0);
    dashSheet.setColumnWidth(3, 20.0);
    dashSheet.setColumnWidth(4, 20.0);
    dashSheet.setColumnWidth(5, 20.0);
    dashSheet.setColumnWidth(6, 20.0);
    dashSheet.setColumnWidth(7, 18.0);
    dashSheet.setColumnWidth(8, 22.0);
    dashSheet.setColumnWidth(9, 20.0);
    dashSheet.setColumnWidth(10, 20.0);
    dashSheet.setColumnWidth(11, 20.0);
    dashSheet.setColumnWidth(12, 22.0);
    dashSheet.setColumnWidth(13, 20.0);
  }

  // ---------------------------------------------------------------------------
  // Analytics Data Sheets
  // ---------------------------------------------------------------------------
  void _populateReportStatusAnalysis(
    Sheet sheet,
    ReportAggregates agg,
    int regMaxRow,
  ) {
    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('Status');
    sheet.cell(CellIndex.indexByString('B1')).value = TextCellValue('Count');
    sheet.cell(CellIndex.indexByString('C1')).value = TextCellValue(
      'Percentage',
    );
    _styleHeaderRow(sheet, 0, 3, bgColor: sectionHeaderBgColor);

    final statuses = [
      ('Open', "COUNTIF('Action Register'!K2:K$regMaxRow, \"Open\")", agg.open),
      (
        'In Progress',
        "COUNTIF('Action Register'!K2:K$regMaxRow, \"In Progress\")",
        agg.byStatus['In Progress'] ?? 0,
      ),
      (
        'Ready for Review',
        "COUNTIF('Action Register'!K2:K$regMaxRow, \"Ready for Review\") + COUNTIF('Action Register'!K2:K$regMaxRow, \"Pending Review\")",
        agg.pendingReview,
      ),
      (
        'Closed',
        "COUNTIF('Action Register'!K2:K$regMaxRow, \"Closed\")",
        agg.closed,
      ),
      (
        'Overdue',
        "COUNTIF('Action Register'!K2:K$regMaxRow, \"Overdue\")",
        agg.overdue,
      ),
    ];

    for (int s = 0; s < statuses.length; s++) {
      final r = s + 1;
      final st = statuses[s];
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
          .value = TextCellValue(
        st.$1,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r))
          .value = FormulaCellValue(
        st.$2,
        cachedValue: '${st.$3}',
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r))
          .value = FormulaCellValue(
        "IF(\$B\$7>0, B${r + 1}/\$B\$7, 0)",
      );
    }

    // Total row
    sheet.cell(CellIndex.indexByString('A7')).value = TextCellValue('Total');
    sheet.cell(CellIndex.indexByString('B7')).value = FormulaCellValue(
      "SUM(B2:B6)",
      cachedValue: '${agg.total}',
    );
    sheet.cell(CellIndex.indexByString('C7')).value = TextCellValue('100%');
    _styleHeaderRow(sheet, 6, 3, bgColor: subHeaderBgColor);

    sheet.setColumnWidth(0, 22.0);
    sheet.setColumnWidth(1, 14.0);
    sheet.setColumnWidth(2, 16.0);
    sheet.freezePanes(rows: 1, columns: 0);
  }

  void _populateReportProgressAnalysis(
    Sheet sheet,
    ReportAggregates agg,
    int regMaxRow,
  ) {
    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue(
      'Progress Band',
    );
    sheet.cell(CellIndex.indexByString('B1')).value = TextCellValue('Count');
    sheet.cell(CellIndex.indexByString('C1')).value = TextCellValue(
      'Percentage',
    );
    _styleHeaderRow(sheet, 0, 3, bgColor: sectionHeaderBgColor);

    final bands = [
      (
        '0–24%',
        "COUNTIFS('Action Register'!L2:L$regMaxRow, \">=0\", 'Action Register'!L2:L$regMaxRow, \"<=24\")",
        agg.byProgressBand['0–24%'] ?? 0,
      ),
      (
        '25–49%',
        "COUNTIFS('Action Register'!L2:L$regMaxRow, \">=25\", 'Action Register'!L2:L$regMaxRow, \"<=49\")",
        agg.byProgressBand['25–49%'] ?? 0,
      ),
      (
        '50–74%',
        "COUNTIFS('Action Register'!L2:L$regMaxRow, \">=50\", 'Action Register'!L2:L$regMaxRow, \"<=74\")",
        agg.byProgressBand['50–74%'] ?? 0,
      ),
      (
        '75–99%',
        "COUNTIFS('Action Register'!L2:L$regMaxRow, \">=75\", 'Action Register'!L2:L$regMaxRow, \"<=99\")",
        agg.byProgressBand['75–99%'] ?? 0,
      ),
      (
        '100%',
        "COUNTIF('Action Register'!L2:L$regMaxRow, 100)",
        agg.byProgressBand['100%'] ?? 0,
      ),
    ];

    for (int b = 0; b < bands.length; b++) {
      final r = b + 1;
      final band = bands[b];
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
          .value = TextCellValue(
        band.$1,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r))
          .value = FormulaCellValue(
        band.$2,
        cachedValue: '${band.$3}',
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r))
          .value = FormulaCellValue(
        "IF(\$B\$7>0, B${r + 1}/\$B\$7, 0)",
      );
    }

    sheet.cell(CellIndex.indexByString('A7')).value = TextCellValue('Total');
    sheet.cell(CellIndex.indexByString('B7')).value = FormulaCellValue(
      "SUM(B2:B6)",
      cachedValue: '${agg.total}',
    );
    sheet.cell(CellIndex.indexByString('C7')).value = TextCellValue('100%');
    _styleHeaderRow(sheet, 6, 3, bgColor: subHeaderBgColor);

    sheet.setColumnWidth(0, 20.0);
    sheet.setColumnWidth(1, 14.0);
    sheet.setColumnWidth(2, 16.0);
    sheet.freezePanes(rows: 1, columns: 0);
  }

  void _populateReportPriorityAnalysis(
    Sheet sheet,
    ReportAggregates agg,
    int regMaxRow,
  ) {
    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('Priority');
    sheet.cell(CellIndex.indexByString('B1')).value = TextCellValue('Count');
    sheet.cell(CellIndex.indexByString('C1')).value = TextCellValue(
      'Percentage',
    );
    _styleHeaderRow(sheet, 0, 3, bgColor: sectionHeaderBgColor);

    final priorities = [
      (
        'Critical',
        "COUNTIF('Action Register'!J2:J$regMaxRow, \"Critical\")",
        agg.byPriority['Critical'] ?? 0,
      ),
      (
        'High',
        "COUNTIF('Action Register'!J2:J$regMaxRow, \"High\")",
        agg.byPriority['High'] ?? 0,
      ),
      (
        'Medium',
        "COUNTIF('Action Register'!J2:J$regMaxRow, \"Medium\")",
        agg.byPriority['Medium'] ?? 0,
      ),
      (
        'Low',
        "COUNTIF('Action Register'!J2:J$regMaxRow, \"Low\")",
        agg.byPriority['Low'] ?? 0,
      ),
    ];

    for (int p = 0; p < priorities.length; p++) {
      final r = p + 1;
      final pri = priorities[p];
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
          .value = TextCellValue(
        pri.$1,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r))
          .value = FormulaCellValue(
        pri.$2,
        cachedValue: '${pri.$3}',
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r))
          .value = FormulaCellValue(
        "IF(\$B\$6>0, B${r + 1}/\$B\$6, 0)",
      );
    }

    sheet.cell(CellIndex.indexByString('A6')).value = TextCellValue('Total');
    sheet.cell(CellIndex.indexByString('B6')).value = FormulaCellValue(
      "SUM(B2:B5)",
      cachedValue: '${agg.total}',
    );
    sheet.cell(CellIndex.indexByString('C6')).value = TextCellValue('100%');
    _styleHeaderRow(sheet, 5, 3, bgColor: subHeaderBgColor);

    sheet.setColumnWidth(0, 18.0);
    sheet.setColumnWidth(1, 14.0);
    sheet.setColumnWidth(2, 16.0);
    sheet.freezePanes(rows: 1, columns: 0);
  }

  int _populateReportDeptAnalysis(
    Sheet sheet,
    List<ActionRecord> filteredActions,
    int regMaxRow,
  ) {
    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue(
      'Department',
    );
    sheet.cell(CellIndex.indexByString('B1')).value = TextCellValue(
      'Total Actions',
    );
    sheet.cell(CellIndex.indexByString('C1')).value = TextCellValue('Open');
    sheet.cell(CellIndex.indexByString('D1')).value = TextCellValue('Closed');
    sheet.cell(CellIndex.indexByString('E1')).value = TextCellValue(
      'Avg Completion %',
    );
    _styleHeaderRow(sheet, 0, 5, bgColor: sectionHeaderBgColor);

    final depts = filteredActions
        .map((a) => a.department.trim())
        .where((d) => d.isNotEmpty)
        .toSet()
        .toList();
    depts.sort();
    if (depts.isEmpty) depts.add('General');

    for (int i = 0; i < depts.length; i++) {
      final r = i + 1;
      final d = depts[i];
      final safeD = d.replaceAll('"', '""');
      final deptActions = filteredActions
          .where((a) => a.department.trim() == d)
          .toList();
      final openCount = deptActions.where((a) => !a.isClosed).length;
      final closedCount = deptActions.where((a) => a.isClosed).length;
      final avg = deptActions.isEmpty
          ? 0
          : (deptActions.map((a) => a.percentComplete).reduce((a, b) => a + b) /
                    deptActions.length)
                .round();

      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
          .value = TextCellValue(
        d,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r))
          .value = FormulaCellValue(
        "COUNTIF('Action Register'!G2:G$regMaxRow, \"$safeD\")",
        cachedValue: '${deptActions.length}',
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r))
          .value = FormulaCellValue(
        "COUNTIFS('Action Register'!G2:G$regMaxRow, \"$safeD\", 'Action Register'!K2:K$regMaxRow, \"<>Closed\")",
        cachedValue: '$openCount',
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r))
          .value = FormulaCellValue(
        "COUNTIFS('Action Register'!G2:G$regMaxRow, \"$safeD\", 'Action Register'!K2:K$regMaxRow, \"Closed\")",
        cachedValue: '$closedCount',
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r))
          .value = FormulaCellValue(
        "IFERROR(AVERAGEIF('Action Register'!G2:G$regMaxRow, \"$safeD\", 'Action Register'!L2:L$regMaxRow), 0)",
        cachedValue: '$avg',
      );
    }

    sheet.setColumnWidth(0, 24.0);
    sheet.setColumnWidth(1, 14.0);
    sheet.setColumnWidth(2, 12.0);
    sheet.setColumnWidth(3, 12.0);
    sheet.setColumnWidth(4, 18.0);
    sheet.freezePanes(rows: 1, columns: 0);

    return depts.length;
  }

  int _populateReportDivAnalysis(
    Sheet sheet,
    List<ActionRecord> filteredActions,
    int regMaxRow,
  ) {
    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('Division');
    sheet.cell(CellIndex.indexByString('B1')).value = TextCellValue(
      'Total Actions',
    );
    sheet.cell(CellIndex.indexByString('C1')).value = TextCellValue('Open');
    sheet.cell(CellIndex.indexByString('D1')).value = TextCellValue('Closed');
    sheet.cell(CellIndex.indexByString('E1')).value = TextCellValue(
      'Avg Completion %',
    );
    _styleHeaderRow(sheet, 0, 5, bgColor: sectionHeaderBgColor);

    final divs = filteredActions
        .map((a) => a.division.trim())
        .where((d) => d.isNotEmpty)
        .toSet()
        .toList();
    divs.sort();
    if (divs.isEmpty) divs.add('Operations');

    for (int i = 0; i < divs.length; i++) {
      final r = i + 1;
      final d = divs[i];
      final safeD = d.replaceAll('"', '""');
      final divActions = filteredActions
          .where((a) => a.division.trim() == d)
          .toList();
      final openCount = divActions.where((a) => !a.isClosed).length;
      final closedCount = divActions.where((a) => a.isClosed).length;
      final avg = divActions.isEmpty
          ? 0
          : (divActions.map((a) => a.percentComplete).reduce((a, b) => a + b) /
                    divActions.length)
                .round();

      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
          .value = TextCellValue(
        d,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r))
          .value = FormulaCellValue(
        "COUNTIF('Action Register'!H2:H$regMaxRow, \"$safeD\")",
        cachedValue: '${divActions.length}',
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r))
          .value = FormulaCellValue(
        "COUNTIFS('Action Register'!H2:H$regMaxRow, \"$safeD\", 'Action Register'!K2:K$regMaxRow, \"<>Closed\")",
        cachedValue: '$openCount',
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r))
          .value = FormulaCellValue(
        "COUNTIFS('Action Register'!H2:H$regMaxRow, \"$safeD\", 'Action Register'!K2:K$regMaxRow, \"Closed\")",
        cachedValue: '$closedCount',
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r))
          .value = FormulaCellValue(
        "IFERROR(AVERAGEIF('Action Register'!H2:H$regMaxRow, \"$safeD\", 'Action Register'!L2:L$regMaxRow), 0)",
        cachedValue: '$avg',
      );
    }

    sheet.setColumnWidth(0, 22.0);
    sheet.setColumnWidth(1, 14.0);
    sheet.setColumnWidth(2, 12.0);
    sheet.setColumnWidth(3, 12.0);
    sheet.setColumnWidth(4, 18.0);
    sheet.freezePanes(rows: 1, columns: 0);

    return divs.length;
  }

  int _populateReportSecAnalysis(
    Sheet sheet,
    List<ActionRecord> filteredActions,
    int regMaxRow,
  ) {
    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('Section');
    sheet.cell(CellIndex.indexByString('B1')).value = TextCellValue(
      'Total Actions',
    );
    sheet.cell(CellIndex.indexByString('C1')).value = TextCellValue('Open');
    sheet.cell(CellIndex.indexByString('D1')).value = TextCellValue('Closed');
    _styleHeaderRow(sheet, 0, 4, bgColor: sectionHeaderBgColor);

    final secs = filteredActions
        .map((a) => a.section.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    secs.sort();
    if (secs.isEmpty) secs.add('General');

    for (int i = 0; i < secs.length; i++) {
      final r = i + 1;
      final s = secs[i];
      final safeS = s.replaceAll('"', '""');
      final secActions = filteredActions
          .where((a) => a.section.trim() == s)
          .toList();
      final openCount = secActions.where((a) => !a.isClosed).length;
      final closedCount = secActions.where((a) => a.isClosed).length;

      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
          .value = TextCellValue(
        s,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r))
          .value = FormulaCellValue(
        "COUNTIF('Action Register'!F2:F$regMaxRow, \"$safeS\")",
        cachedValue: '${secActions.length}',
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r))
          .value = FormulaCellValue(
        "COUNTIFS('Action Register'!F2:F$regMaxRow, \"$safeS\", 'Action Register'!K2:K$regMaxRow, \"<>Closed\")",
        cachedValue: '$openCount',
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r))
          .value = FormulaCellValue(
        "COUNTIFS('Action Register'!F2:F$regMaxRow, \"$safeS\", 'Action Register'!K2:K$regMaxRow, \"Closed\")",
        cachedValue: '$closedCount',
      );
    }

    sheet.setColumnWidth(0, 22.0);
    sheet.setColumnWidth(1, 14.0);
    sheet.setColumnWidth(2, 12.0);
    sheet.setColumnWidth(3, 12.0);
    sheet.freezePanes(rows: 1, columns: 0);

    return secs.length;
  }

  int _populateReportSiteAnalysis(
    Sheet sheet,
    List<ActionRecord> filteredActions,
    int regMaxRow,
  ) {
    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('Site');
    sheet.cell(CellIndex.indexByString('B1')).value = TextCellValue(
      'Total Actions',
    );
    sheet.cell(CellIndex.indexByString('C1')).value = TextCellValue('Open');
    sheet.cell(CellIndex.indexByString('D1')).value = TextCellValue('Closed');
    _styleHeaderRow(sheet, 0, 4, bgColor: sectionHeaderBgColor);

    final sites = filteredActions
        .map((a) => a.site.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    sites.sort();
    if (sites.isEmpty) sites.add('Headquarters');

    for (int i = 0; i < sites.length; i++) {
      final r = i + 1;
      final s = sites[i];
      final safeS = s.replaceAll('"', '""');
      final siteActions = filteredActions
          .where((a) => a.site.trim() == s)
          .toList();
      final openCount = siteActions.where((a) => !a.isClosed).length;
      final closedCount = siteActions.where((a) => a.isClosed).length;

      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
          .value = TextCellValue(
        s,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r))
          .value = FormulaCellValue(
        "COUNTIF('Action Register'!I2:I$regMaxRow, \"$safeS\")",
        cachedValue: '${siteActions.length}',
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r))
          .value = FormulaCellValue(
        "COUNTIFS('Action Register'!I2:I$regMaxRow, \"$safeS\", 'Action Register'!K2:K$regMaxRow, \"<>Closed\")",
        cachedValue: '$openCount',
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r))
          .value = FormulaCellValue(
        "COUNTIFS('Action Register'!I2:I$regMaxRow, \"$safeS\", 'Action Register'!K2:K$regMaxRow, \"Closed\")",
        cachedValue: '$closedCount',
      );
    }

    sheet.setColumnWidth(0, 22.0);
    sheet.setColumnWidth(1, 14.0);
    sheet.setColumnWidth(2, 12.0);
    sheet.setColumnWidth(3, 12.0);
    sheet.freezePanes(rows: 1, columns: 0);

    return sites.length;
  }

  int _populateReportAssigneeAnalysis(
    Sheet sheet,
    List<ActionRecord> filteredActions,
    ReportAggregates agg,
  ) {
    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('Assignee');
    sheet.cell(CellIndex.indexByString('B1')).value = TextCellValue(
      'Total Actions',
    );
    sheet.cell(CellIndex.indexByString('C1')).value = TextCellValue('Open');
    sheet.cell(CellIndex.indexByString('D1')).value = TextCellValue('Closed');
    sheet.cell(CellIndex.indexByString('E1')).value = TextCellValue(
      'Avg Completion %',
    );
    _styleHeaderRow(sheet, 0, 5, bgColor: sectionHeaderBgColor);

    final assignees = agg.byAssignee.entries.toList();
    assignees.sort((a, b) => b.value.compareTo(a.value));
    final topList = assignees.take(15).toList();
    if (topList.isEmpty) {
      topList.add(const MapEntry('Unassigned', 0));
    }

    for (int i = 0; i < topList.length; i++) {
      final r = i + 1;
      final name = topList[i].key;
      final count = topList[i].value;
      final actions = filteredActions.where((a) {
        if (a.isExternalRecipient) {
          return (a.externalRecipientName ?? 'External') == name;
        }
        return a.assignedTo == name;
      }).toList();
      final openCount = actions.where((a) => !a.isClosed).length;
      final closedCount = actions.where((a) => a.isClosed).length;
      final avg = actions.isEmpty
          ? 0
          : (actions.map((a) => a.percentComplete).reduce((a, b) => a + b) /
                    actions.length)
                .round();

      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
          .value = TextCellValue(
        name,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r))
          .value = IntCellValue(
        count,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r))
          .value = IntCellValue(
        openCount,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r))
          .value = IntCellValue(
        closedCount,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r))
          .value = IntCellValue(
        avg,
      );
    }

    sheet.setColumnWidth(0, 24.0);
    sheet.setColumnWidth(1, 14.0);
    sheet.setColumnWidth(2, 12.0);
    sheet.setColumnWidth(3, 12.0);
    sheet.setColumnWidth(4, 18.0);
    sheet.freezePanes(rows: 1, columns: 0);

    return topList.length;
  }

  void _populateReportTimelineAnalysis(Sheet sheet, ReportAggregates agg) {
    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('Month');
    sheet.cell(CellIndex.indexByString('B1')).value = TextCellValue(
      'Actions Raised',
    );
    sheet.cell(CellIndex.indexByString('C1')).value = TextCellValue(
      'Actions Completed',
    );
    sheet.cell(CellIndex.indexByString('D1')).value = TextCellValue(
      'Overdue Actions',
    );
    sheet.cell(CellIndex.indexByString('E1')).value = TextCellValue(
      'Follow-Up Activity',
    );
    _styleHeaderRow(sheet, 0, 5, bgColor: sectionHeaderBgColor);

    final monthly = agg.monthlyTimeline;
    final followUp = agg.followUpTimeline;

    for (int i = 0; i < 12; i++) {
      final r = i + 1;
      final mPoint = i < monthly.length
          ? monthly[i]
          : MonthlyTrendPoint(
              year: 2026,
              month: i + 1,
              label: 'M$i',
              raised: 0,
              closed: 0,
              overdue: 0,
            );
      final fPoint = i < followUp.length
          ? followUp[i]
          : MonthlyFollowUpPoint(
              year: 2026,
              month: i + 1,
              label: 'M$i',
              count: 0,
            );

      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
          .value = TextCellValue(
        mPoint.label,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r))
          .value = IntCellValue(
        mPoint.raised,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r))
          .value = IntCellValue(
        mPoint.closed,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r))
          .value = IntCellValue(
        mPoint.overdue,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r))
          .value = IntCellValue(
        fPoint.count,
      );
    }

    sheet.setColumnWidth(0, 16.0);
    sheet.setColumnWidth(1, 16.0);
    sheet.setColumnWidth(2, 18.0);
    sheet.setColumnWidth(3, 16.0);
    sheet.setColumnWidth(4, 20.0);
    sheet.freezePanes(rows: 1, columns: 0);
  }

  // ---------------------------------------------------------------------------
  // Action Lifecycle, Progress History, Comments, Lists for Report Workbook
  // ---------------------------------------------------------------------------
  void _populateReportLifecycleSheet(
    Sheet lifecycleSheet,
    List<ActionRecord> filteredActions,
  ) {
    final lifecycleHeaders = [
      'Action ID',
      'Subject',
      'Lifecycle Stage',
      'Event Date',
      'Submitted At',
      'Performed By',
      'Status',
      'Progress %',
      'Milestone Notes / Remarks',
    ];

    for (int i = 0; i < lifecycleHeaders.length; i++) {
      lifecycleSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = TextCellValue(
        lifecycleHeaders[i],
      );
    }
    _styleHeaderRow(lifecycleSheet, 0, lifecycleHeaders.length);

    int lRow = 1;
    for (final a in filteredActions) {
      // 1. Created milestone
      lifecycleSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: lRow))
          .value = TextCellValue(
        a.displayId,
      );
      lifecycleSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: lRow))
          .value = TextCellValue(
        a.subject,
      );
      lifecycleSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: lRow))
          .value = TextCellValue(
        'Created',
      );
      lifecycleSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: lRow))
          .value = _parseDate(
        a.dateRaised,
      );
      lifecycleSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: lRow))
          .value = _parseDateTime(
        a.dateRaised,
      );
      lifecycleSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: lRow))
          .value = TextCellValue(
        a.assignedBy.isNotEmpty ? a.assignedBy : 'Creator',
      );
      lifecycleSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: lRow))
          .value = TextCellValue(
        'Open',
      );
      lifecycleSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: lRow))
          .value = IntCellValue(
        0,
      );
      lifecycleSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: lRow))
          .value = TextCellValue(
        a.description.isNotEmpty ? a.description : 'Action logged',
      );
      lRow++;

      // 2. Assigned milestone
      if (a.assignedTo.isNotEmpty && a.assignedTo != 'Unassigned') {
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: lRow))
            .value = TextCellValue(
          a.displayId,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: lRow))
            .value = TextCellValue(
          a.subject,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: lRow))
            .value = TextCellValue(
          'Assigned',
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: lRow))
            .value = _parseDate(
          a.dateRaised,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: lRow))
            .value = _parseDateTime(
          a.dateRaised,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: lRow))
            .value = TextCellValue(
          a.assignedBy,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: lRow))
            .value = TextCellValue(
          a.status,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: lRow))
            .value = IntCellValue(
          0,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: lRow))
            .value = TextCellValue(
          'Assigned to ${a.assignedTo}',
        );
        lRow++;
      }

      // 3. Progress Updates
      for (final u in a.progressUpdates) {
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: lRow))
            .value = TextCellValue(
          a.displayId,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: lRow))
            .value = TextCellValue(
          a.subject,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: lRow))
            .value = TextCellValue(
          'Progress Update',
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: lRow))
            .value = _parseDate(
          u.updateDate,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: lRow))
            .value = _parseDateTime(
          u.createdAt,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: lRow))
            .value = TextCellValue(
          u.updatedByName,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: lRow))
            .value = TextCellValue(
          u.status,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: lRow))
            .value = IntCellValue(
          u.progress,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: lRow))
            .value = TextCellValue(
          u.comments,
        );
        lRow++;
      }

      // 4. Closed milestone
      if (a.isClosed) {
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: lRow))
            .value = TextCellValue(
          a.displayId,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: lRow))
            .value = TextCellValue(
          a.subject,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: lRow))
            .value = TextCellValue(
          'Closed',
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: lRow))
            .value = _parseDate(
          a.closeDate,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: lRow))
            .value = _parseDateTime(
          a.closedAt ?? a.closeDate,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: lRow))
            .value = TextCellValue(
          a.closedByName ?? a.verifiedBy,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: lRow))
            .value = TextCellValue(
          'Closed',
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: lRow))
            .value = IntCellValue(
          100,
        );
        lifecycleSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: lRow))
            .value = TextCellValue(
          a.closureComment.isNotEmpty ? a.closureComment : 'Closure verified',
        );
        lRow++;
      }
    }

    lifecycleSheet.freezePanes(rows: 1, columns: 0);
    lifecycleSheet.setColumnWidth(0, 16.0);
    lifecycleSheet.setColumnWidth(1, 30.0);
    lifecycleSheet.setColumnWidth(2, 22.0);
    lifecycleSheet.setColumnWidth(3, 16.0);
    lifecycleSheet.setColumnWidth(4, 22.0);
    lifecycleSheet.setColumnWidth(5, 20.0);
    lifecycleSheet.setColumnWidth(6, 14.0);
    lifecycleSheet.setColumnWidth(7, 14.0);
    lifecycleSheet.setColumnWidth(8, 35.0);
  }

  void _populateReportProgressHistorySheet(
    Sheet historySheet,
    List<ActionRecord> filteredActions,
  ) {
    final historyHeaders = [
      'Action ID',
      'Subject',
      'Update Date',
      'Submitted At',
      'Updated By',
      'Progress %',
      'Status',
      'Work Update / Comments',
      'Attachments',
    ];

    for (int i = 0; i < historyHeaders.length; i++) {
      historySheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = TextCellValue(
        historyHeaders[i],
      );
    }
    _styleHeaderRow(historySheet, 0, historyHeaders.length);

    int hRow = 1;
    for (final a in filteredActions) {
      if (a.progressUpdates.isNotEmpty) {
        for (final upd in a.progressUpdates) {
          historySheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: hRow))
              .value = TextCellValue(
            a.displayId,
          );
          historySheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: hRow))
              .value = TextCellValue(
            a.subject,
          );
          historySheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: hRow))
              .value = _parseDate(
            upd.updateDate,
          );
          historySheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: hRow))
              .value = _parseDateTime(
            upd.createdAt,
          );
          historySheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: hRow))
              .value = TextCellValue(
            upd.updatedByName,
          );
          historySheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: hRow))
              .value = IntCellValue(
            upd.progress,
          );
          historySheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: hRow))
              .value = TextCellValue(
            upd.status,
          );
          historySheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: hRow))
              .value = TextCellValue(
            upd.comments,
          );
          historySheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: hRow))
              .value = TextCellValue(
            upd.attachments.join(', '),
          );
          hRow++;
        }
      }
    }

    historySheet.freezePanes(rows: 1, columns: 0);
    historySheet.setColumnWidth(0, 16.0);
    historySheet.setColumnWidth(1, 30.0);
    historySheet.setColumnWidth(2, 16.0);
    historySheet.setColumnWidth(3, 22.0);
    historySheet.setColumnWidth(4, 20.0);
    historySheet.setColumnWidth(5, 14.0);
    historySheet.setColumnWidth(6, 14.0);
    historySheet.setColumnWidth(7, 35.0);
    historySheet.setColumnWidth(8, 25.0);
  }

  void _populateReportCommentsSheet(
    Sheet commentsSheet,
    List<ActionRecord> filteredActions,
  ) {
    final commentHeaders = [
      'Action ID',
      'Subject',
      'Date',
      'User',
      'Comment Type',
      'Comment / Review',
      'Status at Time',
      'Progress at Time',
    ];

    for (int i = 0; i < commentHeaders.length; i++) {
      commentsSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = TextCellValue(
        commentHeaders[i],
      );
    }
    _styleHeaderRow(commentsSheet, 0, commentHeaders.length);

    int cRow = 1;
    for (final a in filteredActions) {
      if (a.closureComment.isNotEmpty) {
        commentsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: cRow))
            .value = TextCellValue(
          a.displayId,
        );
        commentsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: cRow))
            .value = TextCellValue(
          a.subject,
        );
        commentsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: cRow))
            .value = _parseDate(
          a.closeDate,
        );
        commentsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: cRow))
            .value = TextCellValue(
          a.closedByName ?? a.verifiedBy,
        );
        commentsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: cRow))
            .value = TextCellValue(
          'Closure Verification',
        );
        commentsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: cRow))
            .value = TextCellValue(
          a.closureComment,
        );
        commentsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: cRow))
            .value = TextCellValue(
          'Closed',
        );
        commentsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: cRow))
            .value = IntCellValue(
          100,
        );
        cRow++;
      }
      for (final upd in a.progressUpdates) {
        if (upd.comments.isNotEmpty) {
          commentsSheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: cRow))
              .value = TextCellValue(
            a.displayId,
          );
          commentsSheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: cRow))
              .value = TextCellValue(
            a.subject,
          );
          commentsSheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: cRow))
              .value = _parseDate(
            upd.updateDate,
          );
          commentsSheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: cRow))
              .value = TextCellValue(
            upd.updatedByName,
          );
          commentsSheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: cRow))
              .value = TextCellValue(
            'Work Progress Note',
          );
          commentsSheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: cRow))
              .value = TextCellValue(
            upd.comments,
          );
          commentsSheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: cRow))
              .value = TextCellValue(
            upd.status,
          );
          commentsSheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: cRow))
              .value = IntCellValue(
            upd.progress,
          );
          cRow++;
        }
      }
    }

    commentsSheet.freezePanes(rows: 1, columns: 0);
    commentsSheet.setColumnWidth(0, 16.0);
    commentsSheet.setColumnWidth(1, 30.0);
    commentsSheet.setColumnWidth(2, 16.0);
    commentsSheet.setColumnWidth(3, 20.0);
    commentsSheet.setColumnWidth(4, 22.0);
    commentsSheet.setColumnWidth(5, 35.0);
    commentsSheet.setColumnWidth(6, 14.0);
    commentsSheet.setColumnWidth(7, 16.0);
  }

  void _populateReportListsSheet(
    Sheet listsSheet,
    List<ActionRecord> filteredActions,
  ) {
    final listHeaders = [
      'Status Values',
      'Priority Values',
      'Progress Bands',
      'Sites',
      'Departments',
      'Divisions',
      'Sections',
    ];

    for (int i = 0; i < listHeaders.length; i++) {
      listsSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = TextCellValue(
        listHeaders[i],
      );
    }
    _styleHeaderRow(
      listsSheet,
      0,
      listHeaders.length,
      bgColor: subHeaderBgColor,
    );

    final statusList = [
      'Open',
      'In Progress',
      'Ready for Review',
      'Closed',
      'Overdue',
    ];
    final priorityList = ['Critical', 'High', 'Medium', 'Low'];
    final progressBands = ['0–24%', '25–49%', '50–74%', '75–99%', '100%'];
    final siteSet =
        filteredActions
            .map((a) => a.site.trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final deptSet =
        filteredActions
            .map((a) => a.department.trim())
            .where((d) => d.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final divSet =
        filteredActions
            .map((a) => a.division.trim())
            .where((d) => d.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final secSet =
        filteredActions
            .map((a) => a.section.trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    final maxLen = [
      statusList.length,
      priorityList.length,
      progressBands.length,
      siteSet.length,
      deptSet.length,
      divSet.length,
      secSet.length,
    ].reduce((a, b) => a > b ? a : b);

    for (int i = 0; i < maxLen; i++) {
      final rIdx = i + 1;
      if (i < statusList.length) {
        listsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rIdx))
            .value = TextCellValue(
          statusList[i],
        );
      }
      if (i < priorityList.length) {
        listsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rIdx))
            .value = TextCellValue(
          priorityList[i],
        );
      }
      if (i < progressBands.length) {
        listsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rIdx))
            .value = TextCellValue(
          progressBands[i],
        );
      }
      if (i < siteSet.length) {
        listsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rIdx))
            .value = TextCellValue(
          siteSet[i],
        );
      }
      if (i < deptSet.length) {
        listsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rIdx))
            .value = TextCellValue(
          deptSet[i],
        );
      }
      if (i < divSet.length) {
        listsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rIdx))
            .value = TextCellValue(
          divSet[i],
        );
      }
      if (i < secSet.length) {
        listsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rIdx))
            .value = TextCellValue(
          secSet[i],
        );
      }
    }
    listsSheet.freezePanes(rows: 1, columns: 0);
  }
}
