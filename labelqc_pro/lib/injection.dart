import 'package:get_it/get_it.dart';
import 'data/datasources/local/database/app_database.dart';
import 'services/iso/iso_analyzers.dart';
import 'services/iso/analysis_engine.dart';
import 'services/spc/spc_and_recommendations.dart';
import 'services/pdf/pdf_generator.dart';

final getIt = GetIt.instance;

Future<void> configureDependencies() async {
  // Database singleton
  getIt.registerSingleton<AppDatabase>(AppDatabase());

  // ISO Analyzers
  getIt.registerLazySingleton<ISO15415Analyzer>(() => ISO15415Analyzer());
  getIt.registerLazySingleton<ISO15416Analyzer>(() => ISO15416Analyzer());

  // Motor central de análisis — encapsula NV21, orientación, crop y ISO
  getIt.registerLazySingleton<BarcodeAnalysisEngine>(() => BarcodeAnalysisEngine(
    analyzer1D: getIt<ISO15416Analyzer>(),
    analyzer2D: getIt<ISO15415Analyzer>(),
  ));

  // Services
  getIt.registerLazySingleton<SPCAnalyzer>(() => SPCAnalyzer());
  getIt.registerLazySingleton<RecommendationEngine>(() => RecommendationEngine());
  getIt.registerLazySingleton<PatternComparator>(() => PatternComparator());
  getIt.registerLazySingleton<VerificationPdfGenerator>(() => VerificationPdfGenerator());
}
