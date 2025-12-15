// lib/main.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/product_screen.dart';
import 'screens/purchase_screen.dart';
import 'screens/sales_screen.dart';
import 'screens/returns_screen.dart';
import 'screens/stock_report_screen.dart';
import 'screens/purchase_report_screen.dart';
import 'screens/sales_report_screen.dart';
import 'screens/returns_report_screen.dart';
import 'screens/total_sales_report_screen.dart';
import 'screens/financial_statistics_screen.dart';
import 'screens/customer_screen.dart';
import 'screens/supplier_screen.dart';
import 'screens/employee_screen.dart';
import 'screens/income_screen.dart';
import 'screens/remittance_screen.dart';
import 'screens/sales_income_analysis_screen.dart';
import 'screens/purchase_remittance_analysis_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/data_assistant_screen.dart';
import 'screens/auto_backup_screen.dart';
import 'screens/auto_backup_list_screen.dart';
import 'screens/version_info_screen.dart';
import 'screens/model_settings_screen.dart';
import 'services/auto_backup_service.dart';

void main() {
  // 为桌面平台初始化SQLite
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    // 初始化FFI
    sqfliteFfiInit();
    // 设置全局数据库工厂
    databaseFactory = databaseFactoryFfi;
  }
  
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _didBackupOnExitThisSession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 当应用进入后台或被关闭时，尝试执行一次“退出时自动备份”（如果开启）
    if ((state == AppLifecycleState.paused || state == AppLifecycleState.detached) &&
        !_didBackupOnExitThisSession) {
      _didBackupOnExitThisSession = true;
      AutoBackupService().backupOnExitIfNeeded();
    }

    // 当应用重新回到前台时，重置本次会话的备份标记
    if (state == AppLifecycleState.resumed) {
      _didBackupOnExitThisSession = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Agrisale',
      // 配置中文本地化
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        // 确保 table_calendar 支持中文
        DefaultMaterialLocalizations.delegate,
      ],
      supportedLocales: [
        const Locale('zh', 'CN'), // 简体中文
      ],
      locale: const Locale('zh', 'CN'), // 设置默认语言为中文
      theme: ThemeData(
        primarySwatch: Colors.green, // 使用绿色作为主色调，与农资主题相符
        colorScheme: ColorScheme.fromSwatch(
          primarySwatch: Colors.green,
          accentColor: Colors.lightGreen, // 强调色
          brightness: Brightness.light,
        ),
        // 只在Windows平台设置字体，解决中文字体不一致问题，不影响其他平台
        textTheme: Platform.isWindows ? GoogleFonts.notoSansScTextTheme() : null,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        appBarTheme: AppBarTheme(
          elevation: 0,
          centerTitle: true,
          backgroundColor: Colors.green,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          filled: true,
          fillColor: Colors.grey[100],
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        listTileTheme: ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        ),
        dataTableTheme: DataTableThemeData(
          headingRowColor: MaterialStateProperty.all(Colors.green[50]),
          dividerThickness: 1,
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => LoginScreen(),
        '/main': (context) => MainScreen(),
        '/products': (context) => ProductScreen(),
        '/purchases': (context) => PurchaseScreen(),
        '/sales': (context) => SalesScreen(),
        '/returns': (context) => ReturnsScreen(),
        '/income': (context) => IncomeScreen(),
        '/remittance': (context) => RemittanceScreen(),
        '/stock_report': (context) => StockReportScreen(),
        '/purchase_report': (context) => PurchaseReportScreen(),
        '/sales_report': (context) => SalesReportScreen(),
        '/returns_report': (context) => ReturnsReportScreen(),
        '/total_sales_report': (context) => TotalSalesReportScreen(),
        '/sales_income_analysis': (context) => SalesIncomeAnalysisScreen(),
        '/purchase_remittance_analysis': (context) => PurchaseRemittanceAnalysisScreen(),
        '/financial_statistics': (context) => FinancialStatisticsScreen(),
        '/customers': (context) => CustomerScreen(),
        '/suppliers': (context) => SupplierScreen(),
        '/employees': (context) => EmployeeScreen(),
        '/settings': (context) => SettingsScreen(),
        '/data_assistant': (context) => DataAssistantScreen(),
        '/auto_backup': (context) => AutoBackupScreen(),
        '/auto_backup_list': (context) => AutoBackupListScreen(),
        '/version_info': (context) => VersionInfoScreen(),
        '/model_settings': (context) => ModelSettingsScreen(),
      },
    );
  }
}