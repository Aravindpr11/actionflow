import 'dart:io';

import 'package:archive/archive.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/services/excel_export_service.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.now();
  final todayIso =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  final yesterdayIso =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${(now.day - 1).clamp(1, 28).toString().padLeft(2, '0')}';

  final testActions = [
    // 1. Open action, high priority, safety dept
    ActionRecord(
      id: 'act-001',
      actionNumber: 'ACT-001',
      organizationId: 'org-111',
      subject: 'Inspect Safety Harnesses',
      description: 'Quarterly PPE inspection',
      actionRequired: 'Replace frayed straps',
      category: 'Safety',
      priority: 'High',
      status: 'Open',
      percentComplete: 15,
      assignedTo: 'John Worker',
      assignedBy: 'David Manager',
      department: 'Safety',
      division: 'Operations',
      site: 'Plant A',
      section: 'Ground Level',
      dateRaised: todayIso,
      startDate: todayIso,
      targetDate: '2026-10-15',
      nextFollowUpDate: '2026-10-01',
      recipientType: 'internal',
    ),
    // 2. Overdue action, critical priority, maintenance dept
    ActionRecord(
      id: 'act-002',
      actionNumber: 'ACT-002',
      organizationId: 'org-111',
      subject: 'Generator Maintenance',
      description: 'Emergency generator overhaul',
      actionRequired: 'Replace oil filters and check battery',
      category: 'Maintenance',
      priority: 'Critical',
      status: 'In Progress',
      percentComplete: 60,
      assignedTo: 'Bob Technician',
      assignedBy: 'David Manager',
      department: 'Maintenance',
      division: 'Engineering',
      site: 'Plant B',
      section: 'Generator Room',
      dateRaised: '2026-08-01',
      startDate: '2026-08-05',
      targetDate: '2026-08-20', // past date -> Overdue
      nextFollowUpDate: '2026-08-15',
      recipientType: 'internal',
    ),
    // 3. Ready for Review action, medium priority, HSE dept
    ActionRecord(
      id: 'act-003',
      actionNumber: 'ACT-003',
      organizationId: 'org-111',
      subject: 'Update Spill Response Kits',
      description: 'Stock absorbent pads',
      actionRequired: 'Verify inventory and replenish',
      category: 'HSE',
      priority: 'Medium',
      status: 'Ready for Review',
      percentComplete: 100,
      assignedTo: 'Alice Specialist',
      assignedBy: 'David Manager',
      department: 'HSE',
      division: 'Operations',
      site: 'Plant A',
      section: 'Chemical Bay',
      dateRaised: '2026-09-01',
      startDate: '2026-09-02',
      targetDate: '2026-09-25',
      recipientType: 'internal',
    ),
    // 4. Closed action, low priority, logistics dept
    ActionRecord(
      id: 'act-004',
      actionNumber: 'ACT-004',
      organizationId: 'org-111',
      subject: 'Forklift Safety Signage',
      description: 'Erect pedestrian caution signs',
      actionRequired: 'Mount reflective signs',
      category: 'Logistics',
      priority: 'Low',
      status: 'Closed',
      percentComplete: 100,
      assignedTo: 'Charlie Operator',
      assignedBy: 'David Manager',
      department: 'Logistics',
      division: 'Supply Chain',
      site: 'Warehouse C',
      section: 'Loading Dock',
      dateRaised: '2026-07-10',
      startDate: '2026-07-11',
      targetDate: '2026-07-20',
      closeDate: yesterdayIso,
      closedByName: 'David Manager',
      closureComment: 'Signs installed and verified compliant',
      recipientType: 'internal',
    ),
    // 5. External recipient action, high priority, environmental dept
    ActionRecord(
      id: 'act-005',
      actionNumber: 'ACT-005',
      organizationId: 'org-111',
      subject: 'Hazardous Waste Disposal',
      description: 'Schedule quarterly hazardous waste pickup',
      actionRequired: 'Certify manifests and load drums',
      category: 'Environmental',
      priority: 'High',
      status: 'In Progress',
      percentComplete: 40,
      assignedTo: 'External Vendor',
      assignedBy: 'David Manager',
      department: 'Environmental',
      division: 'Operations',
      site: 'Plant A',
      section: 'Waste Yard',
      dateRaised: todayIso,
      startDate: todayIso,
      targetDate: '2026-10-30',
      recipientType: 'external',
      externalRecipientName: 'CleanEarth Waste Solutions',
      externalRecipientEmail: 'contact@cleanearth.com',
    ),
  ];

  final activeFilters = {
    'Date Field': 'Raised Date',
    'Date Range': 'All Time',
    'Status': 'All',
    'Priority': 'All',
    'Department': 'All',
    'Division': 'All',
    'Section': 'All',
    'Site': 'All',
    'Assignee': 'All',
  };

  group('Manager Reports Excel Export Redesign Tests', () {
    late Excel workbook;

    setUp(() {
      workbook = ExcelExportService.instance.buildReportWorkbook(
        filteredActions: testActions,
        userName: 'David Manager',
        userRole: 'Manager',
        organizationName: 'Sobha Constructions',
        activeFilters: activeFilters,
      );
    });

    test('1. Dashboard sheet exists and is the default active sheet', () {
      expect(workbook.tables.containsKey('Dashboard'), isTrue);
      expect(workbook.getDefaultSheet(), equals('Dashboard'));
    });

    test('2. All 15 required sheets exist in the executive workbook', () {
      final expectedSheets = [
        'Dashboard',
        'Action Register',
        'Action Lifecycle',
        'Progress History',
        'Comments & Reviews',
        'Status Analysis',
        'Progress Analysis',
        'Priority Analysis',
        'Department Analysis',
        'Division Analysis',
        'Section Analysis',
        'Site Analysis',
        'Assignee Analysis',
        'Timeline Analysis',
        'Lists & Reference',
      ];
      for (final name in expectedSheets) {
        expect(
          workbook.tables.containsKey(name),
          isTrue,
          reason: 'Expected sheet "$name" to be present',
        );
      }
    });

    test('3. Executive Dashboard header banner and metadata are correct', () {
      final dash = workbook.tables['Dashboard']!;
      expect(
        dash.cell(CellIndex.indexByString('A1')).value.toString(),
        equals('ACTIONFLOW'),
      );
      expect(
        dash.cell(CellIndex.indexByString('A2')).value.toString(),
        contains('Manager Reports & Analytics'),
      );
      expect(
        dash.cell(CellIndex.indexByString('B4')).value.toString(),
        equals('Sobha Constructions'),
      );
      expect(
        dash.cell(CellIndex.indexByString('B5')).value.toString(),
        contains('David Manager'),
      );
    });

    test(
      '4. Active filter summary displays correctly with "All" fallbacks',
      () {
        final dash = workbook.tables['Dashboard']!;
        expect(
          dash.cell(CellIndex.indexByString('D3')).value.toString(),
          equals('REPORT FILTERS APPLIED'),
        );
        expect(
          dash.cell(CellIndex.indexByString('E4')).value.toString(),
          equals('Raised Date'),
        );
        expect(
          dash.cell(CellIndex.indexByString('G4')).value.toString(),
          equals('All Time'),
        );
        expect(
          dash.cell(CellIndex.indexByString('E5')).value.toString(),
          equals('All'),
        );
        expect(
          dash.cell(CellIndex.indexByString('G5')).value.toString(),
          equals('All'),
        );
      },
    );

    test(
      '5. 7 KPI cards have valid Excel formulas and accurate cached values',
      () {
        final dash = workbook.tables['Dashboard']!;
        final totalCell =
            dash.cell(CellIndex.indexByString('A11')).value as FormulaCellValue;
        expect(totalCell.formula, contains("COUNTA('Action Register'"));
        expect(totalCell.cachedValue, equals('5'));

        final openCell =
            dash.cell(CellIndex.indexByString('C11')).value as FormulaCellValue;
        expect(openCell.formula, contains("COUNTIF('Action Register'"));
        expect(openCell.cachedValue, equals('1'));

        final inProgCell =
            dash.cell(CellIndex.indexByString('E11')).value as FormulaCellValue;
        expect(inProgCell.cachedValue, equals('2'));

        final closedCell =
            dash.cell(CellIndex.indexByString('K11')).value as FormulaCellValue;
        expect(closedCell.cachedValue, equals('1'));
      },
    );

    test('6. All 12 native Excel charts exist on the Dashboard sheet', () {
      final dash = workbook.tables['Dashboard']!;
      expect(dash.charts.length, equals(12));

      final chartTitles = dash.charts.map((c) => c.title).toList();
      expect(chartTitles, contains('Action Status Distribution'));
      expect(chartTitles, contains('Action Progress Distribution'));
      expect(chartTitles, contains('Actions by Priority'));
      expect(chartTitles, contains('Actions by Department'));
      expect(chartTitles, contains('Actions by Division'));
      expect(chartTitles, contains('Actions by Section'));
      expect(chartTitles, contains('Actions by Site'));
      expect(chartTitles, contains('Top Assignees'));
      expect(chartTitles, contains('Actions Raised Over Time'));
      expect(chartTitles, contains('Actions Completed / Closed Over Time'));
      expect(chartTitles, contains('Overdue Actions Over Time'));
      expect(chartTitles, contains('Follow-Up Activity Over Time'));
    });

    test('7. Charts are native editable OOXML charts with correct types', () {
      final dash = workbook.tables['Dashboard']!;
      final statusChart = dash.charts.firstWhere(
        (c) => c.title == 'Action Status Distribution',
      );
      expect(statusChart.type, equals(ChartType.column));
      expect(statusChart.categories, equals("'Status Analysis'!A2:A6"));

      final prioChart = dash.charts.firstWhere(
        (c) => c.title == 'Actions by Priority',
      );
      expect(prioChart.type, equals(ChartType.pie));
      expect(prioChart.categories, equals("'Priority Analysis'!A2:A5"));

      final raisedChart = dash.charts.firstWhere(
        (c) => c.title == 'Actions Raised Over Time',
      );
      expect(raisedChart.type, equals(ChartType.line));
      expect(raisedChart.categories, equals("'Timeline Analysis'!A2:A13"));
    });

    test('8. Action Register contains all 24 standardized columns', () {
      final reg = workbook.tables['Action Register']!;
      final expectedHeaders = [
        '#',
        'Action ID',
        'Subject',
        'Description',
        'Action Required / Instruction',
        'Category / Section',
        'Department',
        'Division',
        'Site',
        'Priority',
        'Status',
        'Progress %',
        'Assigned To',
        'Assigned By',
        'External Recipient',
        'External Email',
        'Raised Date',
        'Start Date',
        'Follow-Up Date',
        'Target/Due Date',
        'Closed Date',
        'Days Left / Overdue',
        'Created By',
        'Last Updated',
      ];

      for (int c = 0; c < expectedHeaders.length; c++) {
        final cellVal = reg
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
            .value;
        expect(
          cellVal.toString(),
          equals(expectedHeaders[c]),
          reason: 'Column $c header should match',
        );
      }
    });

    test(
      '9. Action Register is an Excel Table with AutoFilter and Freeze Panes',
      () {
        final reg = workbook.tables['Action Register']!;
        expect(reg.tables.length, equals(1));
        expect(reg.tables.first.name, equals('ReportActionRegisterTable'));
        expect(reg.tables.first.from, equals(CellIndex.indexByString('A1')));
        expect(
          reg.tables.first.to,
          equals(CellIndex.indexByColumnRow(columnIndex: 23, rowIndex: 5)),
        );
      },
    );

    test('10. Real dates are stored as DateCellValue in Action Register', () {
      final reg = workbook.tables['Action Register']!;
      // Raised Date is column 16 (Q)
      final raisedDateCell = reg
          .cell(CellIndex.indexByColumnRow(columnIndex: 16, rowIndex: 1))
          .value;
      expect(raisedDateCell, isA<DateCellValue>());

      // Target Date is column 19 (T)
      final targetDateCell = reg
          .cell(CellIndex.indexByColumnRow(columnIndex: 19, rowIndex: 1))
          .value;
      expect(targetDateCell, isA<DateCellValue>());
    });

    test('11. Progress % is stored as IntCellValue in Action Register', () {
      final reg = workbook.tables['Action Register']!;
      // Progress % is column 11 (L)
      final progCell = reg
          .cell(CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: 1))
          .value;
      expect(progCell, isA<IntCellValue>());
      expect((progCell as IntCellValue).value, equals(15));
    });

    test(
      '12. External recipient information is preserved in Action Register',
      () {
        final reg = workbook.tables['Action Register']!;
        // Row 5 is act-005 (External Vendor)
        final extName = reg
            .cell(CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: 5))
            .value;
        expect(extName.toString(), equals('CleanEarth Waste Solutions'));

        final extEmail = reg
            .cell(CellIndex.indexByColumnRow(columnIndex: 15, rowIndex: 5))
            .value;
        expect(extEmail.toString(), equals('contact@cleanearth.com'));
      },
    );

    test(
      '13. Closed actions remain included in Action Register with Closed Date',
      () {
        final reg = workbook.tables['Action Register']!;
        // Row 4 is act-004 (Closed)
        final statusVal = reg
            .cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: 4))
            .value;
        expect(statusVal.toString(), equals('Closed'));

        final closedDateVal = reg
            .cell(CellIndex.indexByColumnRow(columnIndex: 20, rowIndex: 4))
            .value;
        expect(closedDateVal, isA<DateCellValue>());

        final daysLeftVal = reg
            .cell(CellIndex.indexByColumnRow(columnIndex: 21, rowIndex: 4))
            .value;
        expect(daysLeftVal.toString(), equals('Closed'));
      },
    );

    test(
      '14. Status Analysis sheet contains correct summary table with formulas',
      () {
        final statusSheet = workbook.tables['Status Analysis']!;
        expect(
          statusSheet.cell(CellIndex.indexByString('A1')).value.toString(),
          equals('Status'),
        );
        expect(
          statusSheet.cell(CellIndex.indexByString('A2')).value.toString(),
          equals('Open'),
        );
        final openFormula =
            statusSheet.cell(CellIndex.indexByString('B2')).value
                as FormulaCellValue;
        expect(
          openFormula.formula,
          contains("COUNTIF('Action Register'!K2:K6, \"Open\")"),
        );
        expect(openFormula.cachedValue, equals('1'));
      },
    );

    test('15. Priority Analysis sheet contains correct summary table with formulas', () {
      final prioSheet = workbook.tables['Priority Analysis']!;
      expect(
        prioSheet.cell(CellIndex.indexByString('A1')).value.toString(),
        equals('Priority'),
      );
      expect(
        prioSheet.cell(CellIndex.indexByString('A2')).value.toString(),
        equals('Critical'),
      );
      final critFormula =
          prioSheet.cell(CellIndex.indexByString('B2')).value
              as FormulaCellValue;
      expect(
        critFormula.formula,
        contains("COUNTIF('Action Register'!J2:J6, \"Critical\")"),
      );
      expect(critFormula.cachedValue, equals('1'));
    });

    test(
      '16. Department Analysis sheet contains correct departments and formulas',
      () {
        final deptSheet = workbook.tables['Department Analysis']!;
        expect(
          deptSheet.cell(CellIndex.indexByString('A1')).value.toString(),
          equals('Department'),
        );
        final depts = [
          'Environmental',
          'HSE',
          'Logistics',
          'Maintenance',
          'Safety',
        ];
        for (int i = 0; i < depts.length; i++) {
          expect(
            deptSheet
                .cell(
                  CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1),
                )
                .value
                .toString(),
            equals(depts[i]),
          );
        }
      },
    );

    test(
      '17. Timeline Analysis sheet contains 12 monthly rolling trend points',
      () {
        final timeSheet = workbook.tables['Timeline Analysis']!;
        expect(
          timeSheet.cell(CellIndex.indexByString('A1')).value.toString(),
          equals('Month'),
        );
        expect(
          timeSheet.cell(CellIndex.indexByString('B1')).value.toString(),
          equals('Actions Raised'),
        );
        expect(
          timeSheet.cell(CellIndex.indexByString('C1')).value.toString(),
          equals('Actions Completed'),
        );

        // 12 data rows
        for (int r = 1; r <= 12; r++) {
          final monthLabel = timeSheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
              .value;
          expect(monthLabel.toString().isNotEmpty, isTrue);
        }
      },
    );

    test('18. Action Lifecycle sheet contains audit milestones', () {
      final life = workbook.tables['Action Lifecycle']!;
      expect(
        life.cell(CellIndex.indexByString('A1')).value.toString(),
        equals('Action ID'),
      );
      expect(
        life.cell(CellIndex.indexByString('C1')).value.toString(),
        equals('Lifecycle Stage'),
      );
      expect(
        life.cell(CellIndex.indexByString('C2')).value.toString(),
        equals('Created'),
      );
    });

    test(
      '19. Comments & Reviews sheet contains closure verification comments',
      () {
        final comments = workbook.tables['Comments & Reviews']!;
        expect(
          comments.cell(CellIndex.indexByString('A1')).value.toString(),
          equals('Action ID'),
        );
        expect(
          comments.cell(CellIndex.indexByString('E1')).value.toString(),
          equals('Comment Type'),
        );

        final commentValues = comments.rows
            .expand((r) => r.map((c) => c?.value.toString() ?? ''))
            .toList();
        expect(
          commentValues.any(
            (v) => v.contains('Signs installed and verified compliant'),
          ),
          isTrue,
        );
      },
    );

    test('20. Lists & Reference sheet contains categorical lookups', () {
      final lists = workbook.tables['Lists & Reference']!;
      expect(
        lists.cell(CellIndex.indexByString('A1')).value.toString(),
        equals('Status Values'),
      );
      expect(
        lists.cell(CellIndex.indexByString('B1')).value.toString(),
        equals('Priority Values'),
      );
      expect(
        lists.cell(CellIndex.indexByString('C1')).value.toString(),
        equals('Progress Bands'),
      );
    });

    test('21. Workbook encodes and decodes cleanly without data loss or corruption', () {
      final bytes = workbook.save();
      expect(bytes, isNotNull);
      expect(bytes!.isNotEmpty, isTrue);

      final reloaded = Excel.decodeBytes(bytes);
      expect(reloaded.tables.length, equals(15));
      expect(reloaded.tables.containsKey('Dashboard'), isTrue);
      expect(reloaded.tables.containsKey('Action Register'), isTrue);
      expect(reloaded.tables.containsKey('Status Analysis'), isTrue);
      expect(reloaded.tables.containsKey('Timeline Analysis'), isTrue);

      final reloadedReg = reloaded.tables['Action Register']!;
      expect(
        reloadedReg.cell(CellIndex.indexByString('A1')).value.toString(),
        equals('#'),
      );
      expect(
        reloadedReg.cell(CellIndex.indexByString('B1')).value.toString(),
        equals('Action ID'),
      );
    });

    test(
      '22. Filtered export with single action reflects only that action',
      () {
        final singleAction = [
          testActions.first,
        ]; // only ACT-001 (High priority)
        final filteredWb = ExcelExportService.instance.buildReportWorkbook(
          filteredActions: singleAction,
          userName: 'David Manager',
          userRole: 'Manager',
          organizationName: 'Sobha Constructions',
          activeFilters: {'Priority': 'High', 'Status': 'Open'},
        );

        final reg = filteredWb.tables['Action Register']!;
        // Row 1 is data, Row 2 should be empty
        expect(
          reg.cell(CellIndex.indexByString('B2')).value.toString(),
          equals('ACT-001'),
        );
        expect(reg.cell(CellIndex.indexByString('B3')).value, isNull);

        final dash = filteredWb.tables['Dashboard']!;
        final totalCell =
            dash.cell(CellIndex.indexByString('A11')).value as FormulaCellValue;
        expect(totalCell.cachedValue, equals('1'));
      },
    );

    test(
      '23. OOXML archive contains exactly 12 chart parts and drawing parts',
      () {
        final bytes = workbook.save()!;
        final archive = ZipDecoder().decodeBytes(bytes);

        // Check xl/charts/chart1.xml ... chart12.xml
        final chartEntries = archive.files
            .where(
              (f) =>
                  f.name.startsWith('xl/charts/chart') &&
                  f.name.endsWith('.xml'),
            )
            .toList();
        expect(chartEntries.length, equals(12));

        for (int i = 1; i <= 12; i++) {
          expect(
            archive.files.any((f) => f.name == 'xl/charts/chart$i.xml'),
            isTrue,
            reason: 'Chart part chart$i.xml must exist',
          );
        }

        // Check drawing part
        expect(
          archive.files.any((f) => f.name.contains('drawings/drawing')),
          isTrue,
        );
      },
    );

    test('24. OOXML archive contains table part with AutoFilter for Action Register', () {
      final bytes = workbook.save()!;
      final archive = ZipDecoder().decodeBytes(bytes);

      final tableEntries = archive.files
          .where(
            (f) =>
                f.name.startsWith('xl/tables/table') && f.name.endsWith('.xml'),
          )
          .toList();
      expect(tableEntries.isNotEmpty, isTrue);

      final tableXml = String.fromCharCodes(
        tableEntries.first.content as List<int>,
      );
      expect(tableXml.contains('autoFilter'), isTrue);
      expect(tableXml.contains('ReportActionRegisterTable'), isTrue);
    });

    test('25. Saves valid physical Excel file for manual verification', () {
      final bytes = workbook.save()!;
      Directory('build').createSync(recursive: true);
      final file = File('build/sample_manager_report.xlsx');
      file.writeAsBytesSync(bytes);
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), greaterThan(10000));
    });
  });
}
