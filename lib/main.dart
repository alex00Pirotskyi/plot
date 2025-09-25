// import 'dart:convert';
// import 'dart:io';
// import 'dart:math';
// import 'package:charts_app/logistic_regression_classifier.dart';
// import 'package:csv/csv.dart';
// import 'package:file_picker/file_picker.dart';
// import 'package:flutter/material.dart';
// import 'package:intl/intl.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:syncfusion_flutter_charts/charts.dart';
// import 'package:path/path.dart' as p;

// void main() {
//   runApp(const CsvChartApp());
// }

// class CsvChartApp extends StatelessWidget {
//   const CsvChartApp({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'CSV Chart Editor',
//       themeMode: ThemeMode.system,
//       theme: ThemeData(
//         colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
//         useMaterial3: true,
//       ),
//       darkTheme: ThemeData(
//         brightness: Brightness.dark,
//         colorScheme: ColorScheme.fromSeed(
//           seedColor: Colors.teal,
//           brightness: Brightness.dark,
//         ),
//         useMaterial3: true,
//       ),
//       home: const ChartViewerPage(),
//     );
//   }
// }

// enum ChartType { line, spline, stepLine }

// class ChartViewerPage extends StatefulWidget {
//   const ChartViewerPage({super.key});
//   @override
//   State<ChartViewerPage> createState() => _ChartViewerPageState();
// }

// class _ChartViewerPageState extends State<ChartViewerPage> {
//   // === STATE VARIABLES ===
//   bool _isProjectExplorerVisible = false;
//   bool _isColumnSelectorVisible = false;
//   bool _isMlPanelVisible = false;
//   double _autoLabelThreshold = 0.8;

//   String? _projectFolderPath;
//   List<FileSystemEntity> _csvFilesInProject = [];
//   File? _currentlyLoadedFile;

//   List<List<dynamic>>? _fullCsvData;
//   List<String>? _fullCsvHeaders;
//   List<List<dynamic>>? _filteredCsvData;
//   List<String>? _filteredCsvHeaders;

//   final Set<int> _tempSelectedColumnIndices = <int>{};

//   late List<ChartData> _chartData = [];
//   late List<ChartData> _originalChartData = [];

//   bool _showMarkers = false;
//   ChartType _selectedChartType = ChartType.line;
//   double _lineWidth = 1.5;
//   double _markerWidth = 4.0;
//   double _markerHeight = 4.0;

//   bool _isEditMode = false;
//   int? _labelColumnIndex;
//   List<dynamic> _uniqueValuesInLabelColumn = [];
//   dynamic _selectedLabelValue;

//   List<double>? _similarityScores;
//   List<int>? _lastUsedFeatureIndices;

//   late ZoomPanBehavior _zoomPanBehavior;

//   static const String _globalSelectedColumnsKey = 'global_selected_columns_v1';

//   @override
//   void initState() {
//     super.initState();
//     _zoomPanBehavior = ZoomPanBehavior(
//       enablePinching: true,
//       enablePanning: true,
//       enableSelectionZooming: true,
//     );
//     _loadInitialFolder().then((loaded) {
//       if (loaded) {
//         setState(() => _isProjectExplorerVisible = true);
//       }
//     });
//     _loadPreferences();
//   }

//   void _showSnackbar(String message, {bool isError = false}) {
//     if (!mounted) return;
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Text(message),
//         backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
//       ),
//     );
//   }

//   Future<bool?> _showConfirmationDialog({
//     required String title,
//     required String content,
//   }) {
//     return showDialog<bool>(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: Text(title),
//         content: Text(content),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(context, false),
//             child: const Text('Cancel'),
//           ),
//           ElevatedButton(
//             onPressed: () => Navigator.pop(context, true),
//             child: const Text('Confirm'),
//           ),
//         ],
//       ),
//     );
//   }

//   // === DATA & FILE HANDLING ===
//   Future<void> _pickProjectFolder() async {
//     String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
//     if (selectedDirectory != null) {
//       final prefs = await SharedPreferences.getInstance();
//       await prefs.setString('project_folder_path', selectedDirectory);
//       setState(() {
//         _projectFolderPath = selectedDirectory;
//         _isProjectExplorerVisible = true;
//         _isColumnSelectorVisible = false;
//         _isMlPanelVisible = false;
//       });
//       _loadFilesInFolder();
//     }
//   }

//   Future<bool> _loadInitialFolder() async {
//     final prefs = await SharedPreferences.getInstance();
//     final savedPath = prefs.getString('project_folder_path');
//     if (savedPath != null) {
//       setState(() {
//         _projectFolderPath = savedPath;
//       });
//       await _loadFilesInFolder();
//       return true;
//     }
//     return false;
//   }

//   Future<void> _loadFilesInFolder() async {
//     if (_projectFolderPath == null) return;
//     try {
//       final dir = Directory(_projectFolderPath!);
//       final files = await dir
//           .list()
//           .where((item) => item.path.toLowerCase().endsWith('.csv'))
//           .toList();
//       setState(
//         () =>
//             _csvFilesInProject = files
//               ..sort((a, b) => a.path.compareTo(b.path)),
//       );
//     } catch (e) {
//       _showSnackbar(
//         'Error reading folder: $e. Please choose a different folder.',
//         isError: true,
//       );
//     }
//   }

//   Future<void> _loadFile(File file) async {
//     try {
//       final fields = await file
//           .openRead()
//           .transform(utf8.decoder)
//           .transform(const CsvToListConverter(shouldParseNumbers: true))
//           .toList();
//       if (fields.isNotEmpty) {
//         setState(() {
//           _currentlyLoadedFile = file;
//           _fullCsvHeaders = fields[0].map((e) => e.toString()).toList();
//           _fullCsvData = fields.sublist(1);
//           _filteredCsvData = null;
//           _similarityScores = null;
//           _lastUsedFeatureIndices = null;
//           _isEditMode = false;
//           _isProjectExplorerVisible = false;
//           _isColumnSelectorVisible = false;
//           _isMlPanelVisible = false;
//         });

//         final prefs = await SharedPreferences.getInstance();
//         final savedHeaders =
//             prefs.getStringList(_globalSelectedColumnsKey) ?? [];
//         final selectedIndices = <int>{};

//         for (final header in savedHeaders) {
//           int index = _fullCsvHeaders!.indexOf(header);
//           if (index != -1) selectedIndices.add(index);
//         }

//         _applyColumnSelection(selectedIndices);
//       }
//     } catch (e) {
//       _showSnackbar('Error loading file: $e', isError: true);
//     }
//   }

//   void _applyColumnSelection(Set<int> selectedIndices) async {
//     if (_fullCsvData == null || _fullCsvHeaders == null) return;

//     final newHeaders = selectedIndices.map((i) => _fullCsvHeaders![i]).toList();
//     final newData = _fullCsvData!
//         .map((row) => selectedIndices.map((index) => row[index]).toList())
//         .toList();

//     setState(() {
//       _filteredCsvHeaders = newHeaders;
//       _filteredCsvData = newData;
//       _chartData = _prepareChartData(_filteredCsvData!);
//       _originalChartData = _prepareChartData(_filteredCsvData!);
//       _labelColumnIndex = null;
//       _selectedLabelValue = null;
//       _uniqueValuesInLabelColumn = [];
//     });

//     final prefs = await SharedPreferences.getInstance();
//     await prefs.setStringList(_globalSelectedColumnsKey, newHeaders);
//   }

//   Future<void> _saveFile({required bool asNew}) async {
//     if (_currentlyLoadedFile == null ||
//         _filteredCsvData == null ||
//         _fullCsvData == null) {
//       _showSnackbar("No data to save.", isError: true);
//       return;
//     }

//     final editedFilteredData = _convertChartDataBackToFiltered();

//     List<List<dynamic>> fullReconstructedData = [];
//     fullReconstructedData.add(_fullCsvHeaders!);

//     for (int i = 0; i < _fullCsvData!.length; i++) {
//       List<dynamic> newFullRow = List.from(_fullCsvData![i]);
//       for (int j = 0; j < _filteredCsvHeaders!.length; j++) {
//         String header = _filteredCsvHeaders![j];
//         int originalIndex = _fullCsvHeaders!.indexOf(header);
//         if (originalIndex != -1) {
//           newFullRow[originalIndex] = editedFilteredData[i][j];
//         }
//       }
//       fullReconstructedData.add(newFullRow);
//     }

//     final csvString = const ListToCsvConverter().convert(fullReconstructedData);

//     String filePath = _currentlyLoadedFile!.path;
//     if (asNew) {
//       final originalName = p.basenameWithoutExtension(filePath);
//       final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
//       final newName = '${originalName}_edited_$timestamp.csv';
//       filePath = p.join(_projectFolderPath!, newName);
//     }

//     if (!asNew) {
//       final confirm = await _showConfirmationDialog(
//         title: 'Overwrite File?',
//         content:
//             'This will replace the original file. This action cannot be undone.',
//       );
//       if (confirm != true) return;
//     }

//     await File(filePath).writeAsString(csvString);
//     _showSnackbar('File saved successfully to $filePath');
//     _loadFilesInFolder();
//   }

//   List<List<dynamic>> _convertChartDataBackToFiltered() {
//     return List.generate(_chartData.length, (i) {
//       List<dynamic> originalFilteredRow = List.from(_filteredCsvData![i]);
//       if (_labelColumnIndex != null) {
//         originalFilteredRow[_labelColumnIndex!] = _chartData[i].label;
//       }
//       return originalFilteredRow;
//     });
//   }

//   // === CHART HELPER METHODS ===
//   List<ChartData> _prepareChartData(List<List<dynamic>> sourceData) {
//     return List.generate(sourceData.length, (i) {
//       final bool isLabel =
//           _labelColumnIndex != null &&
//           _selectedLabelValue != null &&
//           sourceData[i][_labelColumnIndex!] == _selectedLabelValue;

//       return ChartData(
//         index: i,
//         label: isLabel ? _selectedLabelValue : null,
//         values: sourceData[i],
//       );
//     });
//   }

//   void _resetChartEdits() {
//     setState(() {
//       _chartData = _originalChartData.map((d) => ChartData.from(d)).toList();
//       _similarityScores = null;
//       _lastUsedFeatureIndices = null;
//     });
//     _showSnackbar('All edits have been reset.');
//   }

//   void _editDataPoint(ChartPointDetails details) {
//     if (!_isEditMode ||
//         _labelColumnIndex == null ||
//         _selectedLabelValue == null)
//       return;

//     final int index = details.pointIndex!;
//     setState(() {
//       _chartData[index].label = (_chartData[index].label == _selectedLabelValue)
//           ? null
//           : _selectedLabelValue;
//     });
//   }

//   void _updateLabelColumn(int? newIndexInFilteredList) {
//     setState(() {
//       _similarityScores = null;
//       _lastUsedFeatureIndices = null;
//       _selectedLabelValue = null;
//       _uniqueValuesInLabelColumn = [];
//       _labelColumnIndex = newIndexInFilteredList;

//       if (newIndexInFilteredList != null) {
//         final uniqueValues = _filteredCsvData!
//             .map((row) => row[newIndexInFilteredList])
//             .toSet()
//             .where((v) => v != null && v.toString().trim().isNotEmpty)
//             .toList();
//         _uniqueValuesInLabelColumn = uniqueValues;

//         if (_uniqueValuesInLabelColumn.isNotEmpty) {
//           _selectedLabelValue = _uniqueValuesInLabelColumn.first;
//         }
//       }

//       _chartData = _prepareChartData(_filteredCsvData!);
//       _originalChartData = _prepareChartData(_filteredCsvData!);
//     });
//   }

//   // === PREFERENCES ===
//   Future<void> _loadPreferences() async {
//     final prefs = await SharedPreferences.getInstance();
//     setState(() {
//       _lineWidth = prefs.getDouble('chart_line_width') ?? 1.5;
//       _markerWidth = prefs.getDouble('chart_marker_width') ?? 4.0;
//       _markerHeight = prefs.getDouble('chart_marker_height') ?? 4.0;
//       _showMarkers = prefs.getBool('chart_show_markers') ?? false;
//       _selectedChartType = ChartType.values[prefs.getInt('chart_type') ?? 0];
//     });
//   }

//   Future<void> _savePreferences() async {
//     final prefs = await SharedPreferences.getInstance();
//     await prefs.setDouble('chart_line_width', _lineWidth);
//     await prefs.setDouble('chart_marker_width', _markerWidth);
//     await prefs.setDouble('chart_marker_height', _markerHeight);
//     await prefs.setBool('chart_show_markers', _showMarkers);
//     await prefs.setInt('chart_type', _selectedChartType.index);
//   }

//   // === ML & DIALOGS ===

//   Future<void> _runTraining({required bool trainOnAllFiles}) async {
//     if (_labelColumnIndex == null || _selectedLabelValue == null) {
//       _showSnackbar(
//         "Please select a label column and value first.",
//         isError: true,
//       );
//       return;
//     }
//     _showSnackbar("Preparing data and training ML model...");

//     final List<List<double>> xTrain = [];
//     final List<int> yTrain = [];
//     List<int>? featureIndicesForCurrentFile;

//     final List<File> filesToProcess = trainOnAllFiles
//         ? _csvFilesInProject.whereType<File>().toList()
//         : [_currentlyLoadedFile!];

//     for (final file in filesToProcess) {
//       final fields = await file
//           .openRead()
//           .transform(utf8.decoder)
//           .transform(const CsvToListConverter(shouldParseNumbers: true))
//           .toList();
//       if (fields.length < 2) continue;

//       final headers = fields[0].map((e) => e.toString()).toList();
//       final data = fields.sublist(1);

//       final labelHeader = _filteredCsvHeaders![_labelColumnIndex!];
//       final labelColIdxInFile = headers.indexOf(labelHeader);
//       if (labelColIdxInFile == -1) continue;

//       final featureIndicesInFile = <int>[];
//       for (final header in _filteredCsvHeaders!) {
//         if (header == labelHeader) continue;
//         final idx = headers.indexOf(header);
//         if (idx != -1 && data.isNotEmpty && data[0][idx] is num) {
//           featureIndicesInFile.add(idx);
//         }
//       }

//       if (file.path == _currentlyLoadedFile!.path) {
//         featureIndicesForCurrentFile = featureIndicesInFile;
//       }

//       final positiveIndices = <int>{};
//       for (int i = 0; i < data.length; i++) {
//         if (data[i][labelColIdxInFile] == _selectedLabelValue) {
//           positiveIndices.add(i);
//         }
//       }

//       if (positiveIndices.isEmpty) continue;

//       final negativeIndices = <int>{};
//       // BUG FIX: Use a fixed seed for the Random instance to make shuffling deterministic.
//       final allIndices = List.generate(data.length, (i) => i)
//         ..shuffle(Random(42));
//       for (final index in allIndices) {
//         if (negativeIndices.length >= positiveIndices.length * 2)
//           break; // Balance dataset a bit
//         if (!positiveIndices.contains(index)) {
//           negativeIndices.add(index);
//         }
//       }

//       for (final index in positiveIndices) {
//         xTrain.add(
//           featureIndicesInFile
//               .map((colIdx) => (data[index][colIdx] as num).toDouble())
//               .toList(),
//         );
//         yTrain.add(1);
//       }
//       for (final index in negativeIndices) {
//         xTrain.add(
//           featureIndicesInFile
//               .map((colIdx) => (data[index][colIdx] as num).toDouble())
//               .toList(),
//         );
//         yTrain.add(0);
//       }
//     }

//     if (xTrain.isEmpty) {
//       _showSnackbar(
//         "No labels found in the selected file(s) to train on.",
//         isError: true,
//       );
//       return;
//     }

//     // Scale combined training data
//     final List<List<double>> xTrainScaled = [];
//     final minVals = List.filled(xTrain.first.length, double.infinity);
//     final maxVals = List.filled(xTrain.first.length, double.negativeInfinity);

//     for (final sample in xTrain) {
//       for (int i = 0; i < sample.length; i++) {
//         minVals[i] = min(minVals[i], sample[i]);
//         maxVals[i] = max(maxVals[i], sample[i]);
//       }
//     }

//     for (final sample in xTrain) {
//       final scaledSample = <double>[];
//       for (int i = 0; i < sample.length; i++) {
//         final range = maxVals[i] - minVals[i];
//         scaledSample.add(range > 0 ? (sample[i] - minVals[i]) / range : 0);
//       }
//       xTrainScaled.add(scaledSample);
//     }

//     final classifier = LogisticRegressionClassifier(
//       learningRate: 0.5,
//       numIterations: 1000,
//     );
//     classifier.train(xTrainScaled, yTrain);

//     // Scale current file data using same scaler
//     final scaledCurrentFileData = <List<double>>[];
//     for (final row in _fullCsvData!) {
//       final scaledSample = <double>[];
//       for (int i = 0; i < featureIndicesForCurrentFile!.length; i++) {
//         final val = (row[featureIndicesForCurrentFile[i]] as num).toDouble();
//         final range = maxVals[i] - minVals[i];
//         scaledSample.add(range > 0 ? (val - minVals[i]) / range : 0);
//       }
//       scaledCurrentFileData.add(scaledSample);
//     }

//     final scores = classifier.predictForData(scaledCurrentFileData);

//     setState(() {
//       _similarityScores = scores;
//     });
//     _showSnackbar("Model training and prediction complete.");
//   }

//   void _applyAutoLabels() async {
//     if (_similarityScores == null) {
//       _showSnackbar("You must train a model first!", isError: true);
//       return;
//     }

//     final confirm = await _showConfirmationDialog(
//       title: 'Apply Auto-Labels?',
//       content:
//           'This will overwrite existing labels in the current file based on a threshold of ${(_autoLabelThreshold * 100).toStringAsFixed(0)}%. This action cannot be undone.',
//     );

//     if (confirm != true) return;

//     int labelsAdded = 0;
//     int labelsRemoved = 0;

//     setState(() {
//       for (int i = 0; i < _chartData.length; i++) {
//         if (i >= _similarityScores!.length) continue;
//         final score = _similarityScores![i];
//         final currentLabel = _chartData[i].label;

//         if (score >= _autoLabelThreshold) {
//           if (currentLabel == null) labelsAdded++;
//           _chartData[i].label = _selectedLabelValue;
//         } else {
//           if (currentLabel != null) labelsRemoved++;
//           _chartData[i].label = null;
//         }
//       }
//     });

//     _showSnackbar(
//       "Auto-labeling complete. Added: $labelsAdded, Removed: $labelsRemoved.",
//     );
//   }

//   // === CHART SERIES CREATION ===

//   // === CHART SERIES CREATION ===
//   List<CartesianSeries<dynamic, int>> _createSeries() {
//     List<CartesianSeries<dynamic, int>> series = [];
//     if (_filteredCsvHeaders == null) return series;

//     // This series now correctly shows bars only for the points where
//     // the label matches the specifically selected label value.
//     if (_labelColumnIndex != null && _selectedLabelValue != null) {
//       // FIXED
//       series.add(
//         ColumnSeries<ChartData, int>(
//           dataSource: _chartData,
//           xValueMapper: (d, _) => d.index,
//           // A point is an event if its label is not null.
//           yValueMapper: (d, _) => d.label != null ? 1 : 0,
//           name: 'Event: $_selectedLabelValue', // FIXED
//           yAxisName: 'eventAxis',
//           width: 1,
//           onPointTap: _editDataPoint,
//         ),
//       );
//     }

//     for (int i = 0; i < _filteredCsvHeaders!.length; i++) {
//       if (i == _labelColumnIndex) continue;
//       series.add(_getSeriesType(i, _filteredCsvHeaders![i]));
//     }

//     if (_similarityScores != null) {
//       series.add(
//         LineSeries<double, int>(
//           dataSource: _similarityScores!,
//           xValueMapper: (score, index) => index,
//           yValueMapper: (score, _) => score,
//           name: 'Similarity Score',
//           yAxisName: 'similarityAxis',
//           color: Colors.amber,
//           width: 2,
//           dashArray: const <double>[5, 5],
//         ),
//       );
//     }

//     return series;
//   }

//   // === WIDGET BUILDERS ===
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text(
//           _currentlyLoadedFile != null
//               ? p.basename(_currentlyLoadedFile!.path)
//               : 'CSV Chart Editor',
//         ),
//       ),
//       body: Row(
//         children: [
//           NavigationRail(
//             selectedIndex: _isProjectExplorerVisible
//                 ? 0
//                 : _isColumnSelectorVisible
//                 ? 1
//                 : _isMlPanelVisible
//                 ? 2
//                 : null,
//             onDestinationSelected: (index) {
//               switch (index) {
//                 case 0: // Project
//                   setState(() {
//                     if (_projectFolderPath == null) {
//                       _pickProjectFolder();
//                     } else {
//                       _isProjectExplorerVisible = !_isProjectExplorerVisible;
//                       if (_isProjectExplorerVisible) {
//                         _isColumnSelectorVisible = false;
//                         _isMlPanelVisible = false;
//                       }
//                     }
//                   });
//                   break;
//                 case 1: // Columns
//                   if (_fullCsvData != null) {
//                     setState(() {
//                       _isColumnSelectorVisible = !_isColumnSelectorVisible;
//                       if (_isColumnSelectorVisible) {
//                         _tempSelectedColumnIndices.clear();
//                         if (_filteredCsvHeaders != null) {
//                           for (final header in _filteredCsvHeaders!) {
//                             int idx = _fullCsvHeaders!.indexOf(header);
//                             if (idx != -1) _tempSelectedColumnIndices.add(idx);
//                           }
//                         }
//                         _isProjectExplorerVisible = false;
//                         _isMlPanelVisible = false;
//                       }
//                     });
//                   }
//                   break;
//                 case 2: // ML Tools
//                   if (_labelColumnIndex != null &&
//                       _selectedLabelValue != null) {
//                     setState(() {
//                       _isMlPanelVisible = !_isMlPanelVisible;
//                       if (_isMlPanelVisible) {
//                         _isProjectExplorerVisible = false;
//                         _isColumnSelectorVisible = false;
//                       }
//                     });
//                   } else {
//                     _showSnackbar(
//                       "Select a Label Column and Value first to enable ML tools.",
//                       isError: true,
//                     );
//                   }
//                   break;
//                 case 3: // Reset
//                   if (_chartData.isNotEmpty) _resetChartEdits();
//                   break;
//                 case 4: // Edit
//                   if (_chartData.isNotEmpty)
//                     setState(() => _isEditMode = !_isEditMode);
//                   break;
//                 case 5: // Markers
//                   if (_chartData.isNotEmpty) {
//                     if (_showMarkers) {
//                       setState(() => _showMarkers = false);
//                       _savePreferences();
//                     } else {
//                       _showMarkerSizeDialog();
//                     }
//                   }
//                   break;
//                 case 6:
//                   _zoomPanBehavior.zoomIn();
//                   break;
//                 case 7:
//                   _zoomPanBehavior.reset();
//                   break;
//                 case 8:
//                   _zoomPanBehavior.zoomOut();
//                   break;
//                 case 9:
//                   if (_chartData.isNotEmpty) _saveFile(asNew: false);
//                   break;
//                 case 10:
//                   if (_chartData.isNotEmpty) _saveFile(asNew: true);
//                   break;
//                 case 11:
//                   if (_currentlyLoadedFile != null) _deleteCurrentFile();
//                   break;
//               }
//             },
//             labelType: NavigationRailLabelType.all,
//             destinations: [
//               const NavigationRailDestination(
//                 icon: Icon(Icons.folder_open),
//                 label: Text('Project'),
//               ),
//               NavigationRailDestination(
//                 icon: const Icon(Icons.view_column_outlined),
//                 disabled: _fullCsvData == null,
//                 label: const Text('Columns'),
//               ),
//               NavigationRailDestination(
//                 icon: const Icon(Icons.computer, color: Colors.amber),
//                 disabled:
//                     _labelColumnIndex == null || _selectedLabelValue == null,
//                 label: const Text('ML Tools'),
//               ),
//               NavigationRailDestination(
//                 icon: const Icon(Icons.restore),
//                 disabled: _chartData.isEmpty,
//                 label: const Text('Reset'),
//               ),
//               NavigationRailDestination(
//                 icon: Icon(_isEditMode ? Icons.edit_off : Icons.edit),
//                 disabled: _chartData.isEmpty,
//                 label: const Text('Edit'),
//               ),
//               NavigationRailDestination(
//                 icon: Icon(_showMarkers ? Icons.insights : Icons.grain),
//                 disabled: _chartData.isEmpty,
//                 label: const Text('Markers'),
//               ),
//               NavigationRailDestination(
//                 icon: Icon(Icons.zoom_in),
//                 disabled: _chartData.isEmpty,
//                 label: const Text('Zoom In'),
//               ),
//               NavigationRailDestination(
//                 icon: Icon(Icons.restore_page),
//                 disabled: _chartData.isEmpty,
//                 label: const Text('Zoom Reset'),
//               ),
//               NavigationRailDestination(
//                 icon: Icon(Icons.zoom_out),
//                 disabled: _chartData.isEmpty,
//                 label: const Text('Zoom Out'),
//               ),
//               NavigationRailDestination(
//                 icon: const Icon(Icons.save),
//                 disabled: _chartData.isEmpty,
//                 label: const Text('Save'),
//               ),
//               NavigationRailDestination(
//                 icon: const Icon(Icons.save_as),
//                 disabled: _chartData.isEmpty,
//                 label: const Text('Save As'),
//               ),
//               NavigationRailDestination(
//                 icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
//                 disabled: _currentlyLoadedFile == null,
//                 label: const Text('Delete'),
//               ),
//             ],
//           ),
//           const VerticalDivider(thickness: 1, width: 1),
//           Expanded(child: _buildDynamicMainLayout()),
//         ],
//       ),
//     );
//   }

//   Widget _buildDynamicMainLayout() {
//     return Row(
//       children: [
//         if (_isProjectExplorerVisible)
//           SizedBox(width: 250, child: _buildExplorerView()),
//         if (_isProjectExplorerVisible) const VerticalDivider(width: 1),
//         if (_isColumnSelectorVisible)
//           SizedBox(width: 250, child: _buildColumnSelectorPanel()),
//         if (_isColumnSelectorVisible) const VerticalDivider(width: 1),
//         if (_isMlPanelVisible) SizedBox(width: 250, child: _buildMlPanel()),
//         if (_isMlPanelVisible) const VerticalDivider(width: 1),
//         Expanded(
//           child: (_currentlyLoadedFile != null)
//               ? _buildChartView()
//               : _buildWelcomeView(),
//         ),
//       ],
//     );
//   }

//   Widget _buildMlPanel() {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.stretch,
//       children: [
//         Padding(
//           padding: const EdgeInsets.all(16.0),
//           child: Text(
//             'ML Tools',
//             style: Theme.of(context).textTheme.titleMedium,
//           ),
//         ),
//         const Divider(height: 1),
//         Expanded(
//           child: SingleChildScrollView(
//             child: Padding(
//               padding: const EdgeInsets.all(16.0),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     '1. Train Model',
//                     style: Theme.of(context).textTheme.titleSmall,
//                   ),
//                   const SizedBox(height: 8),
//                   SizedBox(
//                     width: double.infinity,
//                     child: ElevatedButton.icon(
//                       icon: const Icon(Icons.model_training),
//                       label: const Text('Train on Current File'),
//                       onPressed: () => _runTraining(trainOnAllFiles: false),
//                     ),
//                   ),
//                   const SizedBox(height: 8),
//                   SizedBox(
//                     width: double.infinity,
//                     child: ElevatedButton.icon(
//                       icon: const Icon(Icons.folder_copy_outlined),
//                       label: const Text('Train on All Project Files'),
//                       onPressed: () => _runTraining(trainOnAllFiles: true),
//                     ),
//                   ),
//                   const SizedBox(height: 24),
//                   const Divider(),
//                   const SizedBox(height: 16),
//                   Text(
//                     '2. Auto-Label by Threshold',
//                     style: Theme.of(context).textTheme.titleSmall,
//                   ),
//                   const SizedBox(height: 8),
//                   Text(
//                     'Apply labels where probability > ${(_autoLabelThreshold * 100).toStringAsFixed(0)}%',
//                   ),
//                   Slider(
//                     value: _autoLabelThreshold,
//                     min: 0.0,
//                     max: 1.0,
//                     divisions: 20,
//                     label: '${(_autoLabelThreshold * 100).toStringAsFixed(0)}%',
//                     onChanged: (value) {
//                       setState(() {
//                         _autoLabelThreshold = value;
//                       });
//                     },
//                   ),
//                   SizedBox(
//                     width: double.infinity,
//                     child: ElevatedButton.icon(
//                       icon: const Icon(Icons.auto_fix_high),
//                       label: const Text('Apply Auto-Labels'),
//                       onPressed: _similarityScores == null
//                           ? null
//                           : _applyAutoLabels,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _buildWelcomeView() {
//     return Center(
//       child: Column(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           const Icon(Icons.folder_open, size: 80, color: Colors.grey),
//           const SizedBox(height: 20),
//           const Text('Select a project folder to begin.'),
//           const SizedBox(height: 20),
//           ElevatedButton.icon(
//             icon: const Icon(Icons.folder),
//             label: const Text('Choose Folder'),
//             onPressed: _pickProjectFolder,
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildExplorerView() {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Padding(
//           padding: const EdgeInsets.all(16.0),
//           child: Text(
//             'Project: ${p.basename(_projectFolderPath ?? "None")}',
//             style: Theme.of(context).textTheme.titleMedium,
//             overflow: TextOverflow.ellipsis,
//           ),
//         ),
//         const Divider(height: 1),
//         Expanded(
//           child: _csvFilesInProject.isEmpty
//               ? const Center(child: Text('No .csv files found in this folder.'))
//               : ListView.builder(
//                   itemCount: _csvFilesInProject.length,
//                   itemBuilder: (context, index) {
//                     final file = _csvFilesInProject[index];
//                     return ListTile(
//                       title: Text(p.basename(file.path)),
//                       leading: const Icon(Icons.description_outlined),
//                       onTap: () => _loadFile(file as File),
//                       selected: _currentlyLoadedFile?.path == file.path,
//                       selectedTileColor: Theme.of(
//                         context,
//                       ).colorScheme.primaryContainer,
//                     );
//                   },
//                 ),
//         ),
//       ],
//     );
//   }

//   Widget _buildColumnSelectorPanel() {
//     if (_fullCsvHeaders == null) {
//       return const Center(child: Text("Load a file first."));
//     }

//     return Column(
//       children: [
//         Padding(
//           padding: const EdgeInsets.all(16.0),
//           child: Text(
//             'Select Columns',
//             style: Theme.of(context).textTheme.titleMedium,
//           ),
//         ),
//         const Divider(height: 1),
//         Expanded(
//           child: ListView.builder(
//             itemCount: _fullCsvHeaders!.length,
//             itemBuilder: (context, index) {
//               return CheckboxListTile(
//                 controlAffinity: ListTileControlAffinity.leading,
//                 title: Text(_fullCsvHeaders![index]),
//                 value: _tempSelectedColumnIndices.contains(index),
//                 onChanged: (isSelected) {
//                   setState(() {
//                     if (isSelected == true) {
//                       _tempSelectedColumnIndices.add(index);
//                     } else {
//                       _tempSelectedColumnIndices.remove(index);
//                     }
//                   });
//                 },
//               );
//             },
//           ),
//         ),
//         const Divider(height: 1),
//         Padding(
//           padding: const EdgeInsets.all(8.0),
//           child: Row(
//             mainAxisAlignment: MainAxisAlignment.end,
//             children: [
//               TextButton(
//                 onPressed: () =>
//                     setState(() => _isColumnSelectorVisible = false),
//                 child: const Text('Cancel'),
//               ),
//               const SizedBox(width: 8),
//               ElevatedButton(
//                 onPressed: () {
//                   _applyColumnSelection(Set.from(_tempSelectedColumnIndices));
//                   setState(() => _isColumnSelectorVisible = false);
//                 },
//                 child: const Text('Apply'),
//               ),
//             ],
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _buildChartView() {
//     if (_filteredCsvData == null) {
//       return const Center(
//         child: Text('Select columns from the side panel to display the chart.'),
//       );
//     }
//     return Column(
//       children: [
//         Padding(
//           padding: const EdgeInsets.all(8.0),
//           child: Column(
//             children: [
//               Row(
//                 children: [
//                   Expanded(
//                     child: DropdownButton<int>(
//                       isExpanded: true,
//                       value: _labelColumnIndex,
//                       hint: const Text('Choose Label Column'),
//                       items: _filteredCsvHeaders!
//                           .asMap()
//                           .entries
//                           .map(
//                             (entry) => DropdownMenuItem<int>(
//                               value: entry.key,
//                               child: Text(entry.value),
//                             ),
//                           )
//                           .toList(),
//                       onChanged: _updateLabelColumn,
//                     ),
//                   ),
//                   const SizedBox(width: 16),
//                   Expanded(
//                     child: DropdownButton<dynamic>(
//                       isExpanded: true,
//                       value: _selectedLabelValue,
//                       hint: const Text('Select Label Value'),
//                       items: _labelColumnIndex == null
//                           ? []
//                           : _uniqueValuesInLabelColumn
//                                 .map(
//                                   (value) => DropdownMenuItem<dynamic>(
//                                     value: value,
//                                     child: Text(value.toString()),
//                                   ),
//                                 )
//                                 .toList(),
//                       onChanged: (newValue) => setState(() {
//                         _selectedLabelValue = newValue;
//                         _similarityScores = null;
//                         _lastUsedFeatureIndices = null;
//                         _chartData = _prepareChartData(_filteredCsvData!);
//                         _originalChartData = _prepareChartData(
//                           _filteredCsvData!,
//                         );
//                       }),
//                     ),
//                   ),
//                 ],
//               ),
//               DropdownButton<ChartType>(
//                 isExpanded: true,
//                 value: _selectedChartType,
//                 hint: const Text('Select Chart Type'),
//                 items: const [
//                   DropdownMenuItem(
//                     value: ChartType.line,
//                     child: Text('Line Chart'),
//                   ),
//                   DropdownMenuItem(
//                     value: ChartType.spline,
//                     child: Text('Spline Chart (Smooth)'),
//                   ),
//                   DropdownMenuItem(
//                     value: ChartType.stepLine,
//                     child: Text('Step Line Chart'),
//                   ),
//                 ],
//                 onChanged: (newType) async {
//                   if (newType != null) await _showLineWidthDialog(newType);
//                 },
//               ),
//             ],
//           ),
//         ),
//         const Divider(height: 1),
//         Expanded(
//           child: SfCartesianChart(
//             primaryXAxis: const NumericAxis(
//               title: AxisTitle(text: 'Sample Index'),
//             ),
//             primaryYAxis: const NumericAxis(
//               title: AxisTitle(text: 'Sensor Value'),
//             ),
//             axes: const <ChartAxis>[
//               NumericAxis(
//                 name: 'eventAxis',
//                 opposedPosition: true,
//                 title: AxisTitle(text: 'Events'),
//                 minimum: 0,
//                 maximum: 1.2,
//                 interval: 1,
//               ),
//               NumericAxis(
//                 name: 'similarityAxis',
//                 opposedPosition: true,
//                 title: AxisTitle(text: 'Similarity'),
//                 minimum: 0,
//                 maximum: 1.05,
//                 interval: 0.25,
//                 majorGridLines: MajorGridLines(width: 0),
//               ),
//             ],
//             legend: const Legend(
//               isVisible: true,
//               position: LegendPosition.bottom,
//             ),
//             tooltipBehavior: TooltipBehavior(
//               enable: true,
//               format: 'series.name : point.y',
//             ),
//             zoomPanBehavior: _zoomPanBehavior,
//             series: _createSeries(),
//           ),
//         ),
//       ],
//     );
//   }
// }

// class ChartData {
//   final int index;
//   dynamic label;
//   final List<dynamic> values;

//   ChartData({required this.index, this.label, required this.values});

//   ChartData.from(ChartData other)
//     : index = other.index,
//       label = other.label,
//       values = List.from(other.values);
// }

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:charts_app/logistic_regression_classifier.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:path/path.dart' as p;

void main() {
  runApp(const CsvChartApp());
}

class CsvChartApp extends StatelessWidget {
  const CsvChartApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CSV Chart Editor',
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ChartViewerPage(),
    );
  }
}

enum ChartType { line, spline, stepLine }

class ChartViewerPage extends StatefulWidget {
  const ChartViewerPage({super.key});
  @override
  State<ChartViewerPage> createState() => _ChartViewerPageState();
}

class _ChartViewerPageState extends State<ChartViewerPage> {
  // === STATE VARIABLES ===
  bool _isProjectExplorerVisible = false;
  bool _isColumnSelectorVisible = false;
  bool _isMlPanelVisible = false;
  double _autoLabelAddThreshold = 0.8;
  double _autoLabelRemoveThreshold = 0.4;

  late TextEditingController _learningRateController;
  late TextEditingController _iterationsController;

  String? _projectFolderPath;
  List<FileSystemEntity> _csvFilesInProject = [];
  File? _currentlyLoadedFile;

  List<List<dynamic>>? _fullCsvData;
  List<String>? _fullCsvHeaders;
  List<List<dynamic>>? _filteredCsvData;
  List<String>? _filteredCsvHeaders;

  final Set<int> _tempSelectedColumnIndices = <int>{};

  late List<ChartData> _chartData = [];
  late List<ChartData> _originalChartData = [];

  bool _showMarkers = false;
  ChartType _selectedChartType = ChartType.line;
  double _lineWidth = 1.5;
  double _markerWidth = 4.0;
  double _markerHeight = 4.0;

  bool _isEditMode = false;
  int? _labelColumnIndex;
  List<dynamic> _uniqueValuesInLabelColumn = [];
  dynamic _selectedLabelValue;

  List<double>? _similarityScores;
  List<int>? _lastUsedFeatureIndices;

  late ZoomPanBehavior _zoomPanBehavior;

  static const String _globalSelectedColumnsKey = 'global_selected_columns_v1';

  @override
  void initState() {
    super.initState();
    _zoomPanBehavior = ZoomPanBehavior(
      enablePinching: true,
      enablePanning: true,
      enableSelectionZooming: true,
    );
    _learningRateController = TextEditingController(text: '0.5');
    _iterationsController = TextEditingController(text: '1000');

    _loadInitialFolder().then((loaded) {
      if (loaded) {
        setState(() => _isProjectExplorerVisible = true);
      }
    });
    _loadPreferences();
  }

  @override
  void dispose() {
    _learningRateController.dispose();
    _iterationsController.dispose();
    super.dispose();
  }

  void _showSnackbar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<bool?> _showConfirmationDialog({
    required String title,
    required String content,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  // === DATA & FILE HANDLING ===
  Future<void> _pickProjectFolder() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('project_folder_path', selectedDirectory);
      setState(() {
        _projectFolderPath = selectedDirectory;
        _isProjectExplorerVisible = true;
        _isColumnSelectorVisible = false;
        _isMlPanelVisible = false;
      });
      _loadFilesInFolder();
    }
  }

  Future<bool> _loadInitialFolder() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString('project_folder_path');
    if (savedPath != null) {
      setState(() {
        _projectFolderPath = savedPath;
      });
      await _loadFilesInFolder();
      return true;
    }
    return false;
  }

  Future<void> _loadFilesInFolder() async {
    if (_projectFolderPath == null) return;
    try {
      final dir = Directory(_projectFolderPath!);
      final files = await dir
          .list()
          .where((item) => item.path.toLowerCase().endsWith('.csv'))
          .toList();
      setState(
        () =>
            _csvFilesInProject = files
              ..sort((a, b) => a.path.compareTo(b.path)),
      );
    } catch (e) {
      _showSnackbar(
        'Error reading folder: $e. Please choose a different folder.',
        isError: true,
      );
    }
  }

  Future<void> _loadFile(File file) async {
    try {
      final fields = await file
          .openRead()
          .transform(utf8.decoder)
          .transform(const CsvToListConverter(shouldParseNumbers: true))
          .toList();
      if (fields.isNotEmpty) {
        setState(() {
          _currentlyLoadedFile = file;
          _fullCsvHeaders = fields[0].map((e) => e.toString()).toList();
          _fullCsvData = fields.sublist(1);
          _filteredCsvData = null;
          _similarityScores = null;
          _lastUsedFeatureIndices = null;
          _isEditMode = false;
          _isProjectExplorerVisible = false;
          _isColumnSelectorVisible = false;
          _isMlPanelVisible = false;
        });

        final prefs = await SharedPreferences.getInstance();
        final savedHeaders =
            prefs.getStringList(_globalSelectedColumnsKey) ?? [];
        final selectedIndices = <int>{};

        for (final header in savedHeaders) {
          int index = _fullCsvHeaders!.indexOf(header);
          if (index != -1) selectedIndices.add(index);
        }

        _applyColumnSelection(selectedIndices);
      }
    } catch (e) {
      _showSnackbar('Error loading file: $e', isError: true);
    }
  }

  void _applyColumnSelection(Set<int> selectedIndices) async {
    if (_fullCsvData == null || _fullCsvHeaders == null) return;

    final newHeaders = selectedIndices.map((i) => _fullCsvHeaders![i]).toList();
    final newData = _fullCsvData!
        .map((row) => selectedIndices.map((index) => row[index]).toList())
        .toList();

    setState(() {
      _filteredCsvHeaders = newHeaders;
      _filteredCsvData = newData;
      _chartData = _prepareChartData(_filteredCsvData!);
      _originalChartData = _prepareChartData(_filteredCsvData!);
      _labelColumnIndex = null;
      _selectedLabelValue = null;
      _uniqueValuesInLabelColumn = [];
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_globalSelectedColumnsKey, newHeaders);
  }

  Future<void> _deleteCurrentFile() async {
    if (_currentlyLoadedFile == null) return;
    final confirm = await _showConfirmationDialog(
      title: 'Delete File?',
      content: 'Permanently delete ${p.basename(_currentlyLoadedFile!.path)}?',
    );
    if (confirm == true) {
      try {
        await _currentlyLoadedFile!.delete();
        _showSnackbar('File deleted.');
        setState(() {
          _currentlyLoadedFile = null;
          _fullCsvData = null;
          _filteredCsvData = null;
          _similarityScores = null;
          _lastUsedFeatureIndices = null;
          _chartData = [];
          _originalChartData = [];
          _isProjectExplorerVisible = true;
        });
        _loadFilesInFolder();
      } catch (e) {
        _showSnackbar('Error deleting file: $e', isError: true);
      }
    }
  }

  Future<void> _saveFile({required bool asNew}) async {
    if (_currentlyLoadedFile == null ||
        _filteredCsvData == null ||
        _fullCsvData == null) {
      _showSnackbar("No data to save.", isError: true);
      return;
    }

    final editedFilteredData = _convertChartDataBackToFiltered();

    List<List<dynamic>> fullReconstructedData = [];
    fullReconstructedData.add(_fullCsvHeaders!);

    for (int i = 0; i < _fullCsvData!.length; i++) {
      List<dynamic> newFullRow = List.from(_fullCsvData![i]);
      for (int j = 0; j < _filteredCsvHeaders!.length; j++) {
        String header = _filteredCsvHeaders![j];
        int originalIndex = _fullCsvHeaders!.indexOf(header);
        if (originalIndex != -1) {
          newFullRow[originalIndex] = editedFilteredData[i][j];
        }
      }
      fullReconstructedData.add(newFullRow);
    }

    final csvString = const ListToCsvConverter().convert(fullReconstructedData);

    String filePath = _currentlyLoadedFile!.path;
    if (asNew) {
      final originalName = p.basenameWithoutExtension(filePath);
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final newName = '${originalName}_edited_$timestamp.csv';
      filePath = p.join(_projectFolderPath!, newName);
    }

    if (!asNew) {
      final confirm = await _showConfirmationDialog(
        title: 'Overwrite File?',
        content:
            'This will replace the original file. This action cannot be undone.',
      );
      if (confirm != true) return;
    }

    await File(filePath).writeAsString(csvString);
    _showSnackbar('File saved successfully to $filePath');
    _loadFilesInFolder();
  }

  List<List<dynamic>> _convertChartDataBackToFiltered() {
    return List.generate(_chartData.length, (i) {
      List<dynamic> originalFilteredRow = List.from(_filteredCsvData![i]);
      if (_labelColumnIndex != null) {
        originalFilteredRow[_labelColumnIndex!] = _chartData[i].label;
      }
      return originalFilteredRow;
    });
  }

  // === CHART HELPER METHODS ===
  List<ChartData> _prepareChartData(List<List<dynamic>> sourceData) {
    return List.generate(sourceData.length, (i) {
      final bool isLabel =
          _labelColumnIndex != null &&
          _selectedLabelValue != null &&
          sourceData[i][_labelColumnIndex!] == _selectedLabelValue;

      return ChartData(
        index: i,
        label: isLabel ? _selectedLabelValue : null,
        values: sourceData[i],
      );
    });
  }

  void _resetChartEdits() {
    setState(() {
      _chartData = _originalChartData.map((d) => ChartData.from(d)).toList();
      _similarityScores = null;
      _lastUsedFeatureIndices = null;
    });
    _showSnackbar('All edits have been reset.');
  }

  void _editDataPoint(ChartPointDetails details) {
    if (!_isEditMode ||
        _labelColumnIndex == null ||
        _selectedLabelValue == null)
      return;

    final int index = details.pointIndex!;
    setState(() {
      _chartData[index].label = (_chartData[index].label == _selectedLabelValue)
          ? null
          : _selectedLabelValue;
    });
  }

  void _updateLabelColumn(int? newIndexInFilteredList) {
    setState(() {
      _similarityScores = null;
      _lastUsedFeatureIndices = null;
      _selectedLabelValue = null;
      _uniqueValuesInLabelColumn = [];
      _labelColumnIndex = newIndexInFilteredList;

      if (newIndexInFilteredList != null) {
        final uniqueValues = _filteredCsvData!
            .map((row) => row[newIndexInFilteredList])
            .toSet()
            .where((v) => v != null && v.toString().trim().isNotEmpty)
            .toList();
        _uniqueValuesInLabelColumn = uniqueValues;

        if (_uniqueValuesInLabelColumn.isNotEmpty) {
          _selectedLabelValue = _uniqueValuesInLabelColumn.first;
        }
      }

      _chartData = _prepareChartData(_filteredCsvData!);
      _originalChartData = _prepareChartData(_filteredCsvData!);
    });
  }

  // === PREFERENCES ===
  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lineWidth = prefs.getDouble('chart_line_width') ?? 1.5;
      _markerWidth = prefs.getDouble('chart_marker_width') ?? 4.0;
      _markerHeight = prefs.getDouble('chart_marker_height') ?? 4.0;
      _showMarkers = prefs.getBool('chart_show_markers') ?? false;
      _selectedChartType = ChartType.values[prefs.getInt('chart_type') ?? 0];
    });
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('chart_line_width', _lineWidth);
    await prefs.setDouble('chart_marker_width', _markerWidth);
    await prefs.setDouble('chart_marker_height', _markerHeight);
    await prefs.setBool('chart_show_markers', _showMarkers);
    await prefs.setInt('chart_type', _selectedChartType.index);
  }

  // === ML & DIALOGS ===

  Future<void> _runTraining({required bool trainOnAllFiles}) async {
    if (_labelColumnIndex == null || _selectedLabelValue == null) {
      _showSnackbar(
        "Please select a label column and value first.",
        isError: true,
      );
      return;
    }
    _showSnackbar("Preparing data and training ML model...");

    final List<List<double>> xTrain = [];
    final List<int> yTrain = [];
    List<int>? featureIndicesForCurrentFile;

    final List<File> filesToProcess = trainOnAllFiles
        ? _csvFilesInProject.whereType<File>().toList()
        : [_currentlyLoadedFile!];

    for (final file in filesToProcess) {
      final fields = await file
          .openRead()
          .transform(utf8.decoder)
          .transform(const CsvToListConverter(shouldParseNumbers: true))
          .toList();
      if (fields.length < 2) continue;

      final headers = fields[0].map((e) => e.toString()).toList();
      final data = fields.sublist(1);

      final labelHeader = _filteredCsvHeaders![_labelColumnIndex!];
      final labelColIdxInFile = headers.indexOf(labelHeader);
      if (labelColIdxInFile == -1) continue;

      final featureIndicesInFile = <int>[];
      for (final header in _filteredCsvHeaders!) {
        if (header == labelHeader) continue;
        final idx = headers.indexOf(header);
        if (idx != -1 && data.isNotEmpty && data[0][idx] is num) {
          featureIndicesInFile.add(idx);
        }
      }

      if (file.path == _currentlyLoadedFile!.path) {
        featureIndicesForCurrentFile = featureIndicesInFile;
      }

      final positiveIndices = <int>{};
      for (int i = 0; i < data.length; i++) {
        if (data[i][labelColIdxInFile] == _selectedLabelValue) {
          positiveIndices.add(i);
        }
      }

      if (positiveIndices.isEmpty) continue;

      final negativeIndices = <int>{};
      final allIndices = List.generate(data.length, (i) => i)
        ..shuffle(Random(42));
      for (final index in allIndices) {
        if (negativeIndices.length >= positiveIndices.length * 2) break;
        if (!positiveIndices.contains(index)) {
          negativeIndices.add(index);
        }
      }

      for (final index in positiveIndices) {
        xTrain.add(
          featureIndicesInFile
              .map((colIdx) => (data[index][colIdx] as num).toDouble())
              .toList(),
        );
        yTrain.add(1);
      }
      for (final index in negativeIndices) {
        xTrain.add(
          featureIndicesInFile
              .map((colIdx) => (data[index][colIdx] as num).toDouble())
              .toList(),
        );
        yTrain.add(0);
      }
    }

    if (xTrain.isEmpty) {
      _showSnackbar(
        "No labels found in the selected file(s) to train on.",
        isError: true,
      );
      return;
    }

    final List<List<double>> xTrainScaled = [];
    final minVals = List.filled(xTrain.first.length, double.infinity);
    final maxVals = List.filled(xTrain.first.length, double.negativeInfinity);

    for (final sample in xTrain) {
      for (int i = 0; i < sample.length; i++) {
        minVals[i] = min(minVals[i], sample[i]);
        maxVals[i] = max(maxVals[i], sample[i]);
      }
    }

    for (final sample in xTrain) {
      final scaledSample = <double>[];
      for (int i = 0; i < sample.length; i++) {
        final range = maxVals[i] - minVals[i];
        scaledSample.add(range > 0 ? (sample[i] - minVals[i]) / range : 0);
      }
      xTrainScaled.add(scaledSample);
    }

    final double learningRate =
        double.tryParse(_learningRateController.text) ?? 0.5;
    final int numIterations = int.tryParse(_iterationsController.text) ?? 1000;

    final classifier = LogisticRegressionClassifier(
      learningRate: learningRate,
      numIterations: numIterations,
    );
    classifier.train(xTrainScaled, yTrain);

    final scaledCurrentFileData = <List<double>>[];
    for (final row in _fullCsvData!) {
      final scaledSample = <double>[];
      for (int i = 0; i < featureIndicesForCurrentFile!.length; i++) {
        final val = (row[featureIndicesForCurrentFile[i]] as num).toDouble();
        final range = maxVals[i] - minVals[i];
        scaledSample.add(range > 0 ? (val - minVals[i]) / range : 0);
      }
      scaledCurrentFileData.add(scaledSample);
    }

    final scores = classifier.predictForData(scaledCurrentFileData);

    setState(() {
      _similarityScores = scores;
    });
    _showSnackbar("Model training and prediction complete.");
  }

  void _applyAutoLabels() async {
    if (_similarityScores == null) {
      _showSnackbar("You must train a model first!", isError: true);
      return;
    }

    final confirm = await _showConfirmationDialog(
      title: 'Apply Auto-Labels?',
      content:
          'This will add labels above ${(_autoLabelAddThreshold * 100).toStringAsFixed(0)}% and remove labels below ${(_autoLabelRemoveThreshold * 100).toStringAsFixed(0)}%. This action cannot be undone.',
    );

    if (confirm != true) return;

    int labelsAdded = 0;
    int labelsRemoved = 0;

    setState(() {
      for (int i = 0; i < _chartData.length; i++) {
        if (i >= _similarityScores!.length) continue;
        final score = _similarityScores![i];
        final currentLabel = _chartData[i].label;

        if (score >= _autoLabelAddThreshold) {
          if (currentLabel == null) labelsAdded++;
          _chartData[i].label = _selectedLabelValue;
        } else if (score < _autoLabelRemoveThreshold) {
          if (currentLabel != null) labelsRemoved++;
          _chartData[i].label = null;
        }
      }
    });

    _showSnackbar(
      "Auto-labeling complete. Added: $labelsAdded, Removed: $labelsRemoved.",
    );
  }

  //   // === DIALOGS ===
  Future<void> _showMarkerSizeDialog() async {
    final widthController = TextEditingController(
      text: _markerWidth.toString(),
    );
    final heightController = TextEditingController(
      text: _markerHeight.toString(),
    );
    final newSizes = await showDialog<Map<String, double>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Marker Size'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: widthController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Width (e.g., 4.0)'),
            ),
            TextField(
              controller: heightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Height (e.g., 4.0)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final width = double.tryParse(widthController.text);
              final height = double.tryParse(heightController.text);
              if (width != null && width > 0 && height != null && height > 0) {
                Navigator.pop(context, {'width': width, 'height': height});
              }
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );

    if (newSizes != null) {
      setState(() {
        _showMarkers = true;
        _markerWidth = newSizes['width']!;
        _markerHeight = newSizes['height']!;
      });
      await _savePreferences();
    }
  }

  Future<void> _showLineWidthDialog(ChartType newType) async {
    final controller = TextEditingController(text: _lineWidth.toString());
    final newWidth = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Line Width'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Width (e.g., 1.5)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(controller.text);
              if (val != null && val > 0) Navigator.pop(context, val);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );

    if (newWidth != null) {
      setState(() {
        _lineWidth = newWidth;
        _selectedChartType = newType;
      });
      await _savePreferences();
    }
  }

  // === CHART SERIES CREATION ===
  List<CartesianSeries<dynamic, int>> _createSeries() {
    List<CartesianSeries<dynamic, int>> series = [];
    if (_filteredCsvHeaders == null) return series;

    if (_labelColumnIndex != null && _selectedLabelValue != null) {
      series.add(
        ColumnSeries<ChartData, int>(
          dataSource: _chartData,
          xValueMapper: (d, _) => d.index,
          yValueMapper: (d, _) => d.label != null ? 1 : 0,
          name: 'Event: $_selectedLabelValue',
          yAxisName: 'eventAxis',
          width: 1,
          onPointTap: _editDataPoint,
        ),
      );
    }

    for (int i = 0; i < _filteredCsvHeaders!.length; i++) {
      if (i == _labelColumnIndex) continue;
      series.add(_getSeriesType(i, _filteredCsvHeaders![i]));
    }

    if (_similarityScores != null) {
      series.add(
        LineSeries<double, int>(
          dataSource: _similarityScores!,
          xValueMapper: (score, index) => index,
          yValueMapper: (score, _) => score,
          name: 'Model Probability',
          yAxisName: 'similarityAxis',
          color: Colors.amber,
          width: 2,
          dashArray: const <double>[5, 5],
        ),
      );
    }

    return series;
  }

  CartesianSeries<ChartData, int> _getSeriesType(int index, String header) {
    final commonProperties = {
      'dataSource': _chartData,
      'xValueMapper': (ChartData data, _) => data.index,
      'yValueMapper': (ChartData data, _) {
        final val = data.values[index];
        return (val is num) ? val.toDouble() : 0.0;
      },
      'name': header,
      'animationDuration': 0.0,
      'width': _lineWidth,
      'onPointTap': _editDataPoint,
      'markerSettings': _showMarkers
          ? MarkerSettings(
              isVisible: true,
              height: _markerHeight,
              width: _markerWidth,
            )
          : const MarkerSettings(isVisible: false),
    };

    switch (_selectedChartType) {
      case ChartType.spline:
        return SplineSeries<ChartData, int>(
          dataSource: commonProperties['dataSource'] as List<ChartData>,
          xValueMapper:
              commonProperties['xValueMapper']
                  as ChartValueMapper<ChartData, int>,
          yValueMapper:
              commonProperties['yValueMapper']
                  as ChartValueMapper<ChartData, num>,
          name: commonProperties['name'] as String,
          animationDuration: commonProperties['animationDuration'] as double,
          width: commonProperties['width'] as double,
          onPointTap:
              commonProperties['onPointTap'] as ChartPointInteractionCallback,
          markerSettings: commonProperties['markerSettings'] as MarkerSettings,
        );
      case ChartType.stepLine:
        return StepLineSeries<ChartData, int>(
          dataSource: commonProperties['dataSource'] as List<ChartData>,
          xValueMapper:
              commonProperties['xValueMapper']
                  as ChartValueMapper<ChartData, int>,
          yValueMapper:
              commonProperties['yValueMapper']
                  as ChartValueMapper<ChartData, num>,
          name: commonProperties['name'] as String,
          animationDuration: commonProperties['animationDuration'] as double,
          width: commonProperties['width'] as double,
          onPointTap:
              commonProperties['onPointTap'] as ChartPointInteractionCallback,
          markerSettings: commonProperties['markerSettings'] as MarkerSettings,
        );
      default:
        return LineSeries<ChartData, int>(
          dataSource: commonProperties['dataSource'] as List<ChartData>,
          xValueMapper:
              commonProperties['xValueMapper']
                  as ChartValueMapper<ChartData, int>,
          yValueMapper:
              commonProperties['yValueMapper']
                  as ChartValueMapper<ChartData, num>,
          name: commonProperties['name'] as String,
          animationDuration: commonProperties['animationDuration'] as double,
          width: commonProperties['width'] as double,
          onPointTap:
              commonProperties['onPointTap'] as ChartPointInteractionCallback,
          markerSettings: commonProperties['markerSettings'] as MarkerSettings,
        );
    }
  }

  // === WIDGET BUILDERS ===
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentlyLoadedFile != null
              ? p.basename(_currentlyLoadedFile!.path)
              : 'CSV Chart Editor',
        ),
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _isProjectExplorerVisible
                ? 0
                : _isColumnSelectorVisible
                ? 1
                : _isMlPanelVisible
                ? 2
                : null,
            onDestinationSelected: (index) {
              switch (index) {
                case 0: // Project
                  setState(() {
                    if (_projectFolderPath == null) {
                      _pickProjectFolder();
                    } else {
                      _isProjectExplorerVisible = !_isProjectExplorerVisible;
                      if (_isProjectExplorerVisible) {
                        _isColumnSelectorVisible = false;
                        _isMlPanelVisible = false;
                      }
                    }
                  });
                  break;
                case 1: // Columns
                  if (_fullCsvData != null) {
                    setState(() {
                      _isColumnSelectorVisible = !_isColumnSelectorVisible;
                      if (_isColumnSelectorVisible) {
                        _tempSelectedColumnIndices.clear();
                        if (_filteredCsvHeaders != null) {
                          for (final header in _filteredCsvHeaders!) {
                            int idx = _fullCsvHeaders!.indexOf(header);
                            if (idx != -1) _tempSelectedColumnIndices.add(idx);
                          }
                        }
                        _isProjectExplorerVisible = false;
                        _isMlPanelVisible = false;
                      }
                    });
                  }
                  break;
                case 2: // ML Tools
                  if (_labelColumnIndex != null &&
                      _selectedLabelValue != null) {
                    setState(() {
                      _isMlPanelVisible = !_isMlPanelVisible;
                      if (_isMlPanelVisible) {
                        _isProjectExplorerVisible = false;
                        _isColumnSelectorVisible = false;
                      }
                    });
                  } else {
                    _showSnackbar(
                      "Select a Label Column and Value first to enable ML tools.",
                      isError: true,
                    );
                  }
                  break;
                case 3: // Reset
                  if (_chartData.isNotEmpty) _resetChartEdits();
                  break;
                case 4: // Edit
                  if (_chartData.isNotEmpty)
                    setState(() => _isEditMode = !_isEditMode);
                  break;
                case 5: // Markers
                  if (_chartData.isNotEmpty) {
                    if (_showMarkers) {
                      setState(() => _showMarkers = false);
                      _savePreferences();
                    } else {
                      _showMarkerSizeDialog();
                    }
                  }
                  break;
                case 6:
                  _zoomPanBehavior.zoomIn();
                  break;
                case 7:
                  _zoomPanBehavior.reset();
                  break;
                case 8:
                  _zoomPanBehavior.zoomOut();
                  break;
                case 9:
                  if (_chartData.isNotEmpty) _saveFile(asNew: false);
                  break;
                case 10:
                  if (_chartData.isNotEmpty) _saveFile(asNew: true);
                  break;
                case 11:
                  if (_currentlyLoadedFile != null) _deleteCurrentFile();
                  break;
              }
            },
            labelType: NavigationRailLabelType.all,
            destinations: [
              const NavigationRailDestination(
                icon: Icon(Icons.folder_open),
                label: Text('Project'),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.view_column_outlined),
                disabled: _fullCsvData == null,
                label: const Text('Columns'),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.computer, color: Colors.amber),
                disabled:
                    _labelColumnIndex == null || _selectedLabelValue == null,
                label: const Text('ML Tools'),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.restore),
                disabled: _chartData.isEmpty,
                label: const Text('Reset'),
              ),
              NavigationRailDestination(
                icon: Icon(_isEditMode ? Icons.edit_off : Icons.edit),
                disabled: _chartData.isEmpty,
                label: const Text('Edit'),
              ),
              NavigationRailDestination(
                icon: Icon(_showMarkers ? Icons.insights : Icons.grain),
                disabled: _chartData.isEmpty,
                label: const Text('Markers'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.zoom_in),
                disabled: _chartData.isEmpty,
                label: const Text('Zoom In'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.restore_page),
                disabled: _chartData.isEmpty,
                label: const Text('Zoom Reset'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.zoom_out),
                disabled: _chartData.isEmpty,
                label: const Text('Zoom Out'),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.save),
                disabled: _chartData.isEmpty,
                label: const Text('Save'),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.save_as),
                disabled: _chartData.isEmpty,
                label: const Text('Save As'),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                disabled: _currentlyLoadedFile == null,
                label: const Text('Delete'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: _buildDynamicMainLayout()),
        ],
      ),
    );
  }

  Widget _buildDynamicMainLayout() {
    return Row(
      children: [
        if (_isProjectExplorerVisible)
          SizedBox(width: 250, child: _buildExplorerView()),
        if (_isProjectExplorerVisible) const VerticalDivider(width: 1),
        if (_isColumnSelectorVisible)
          SizedBox(width: 250, child: _buildColumnSelectorPanel()),
        if (_isColumnSelectorVisible) const VerticalDivider(width: 1),
        if (_isMlPanelVisible) SizedBox(width: 250, child: _buildMlPanel()),
        if (_isMlPanelVisible) const VerticalDivider(width: 1),
        Expanded(
          child: (_currentlyLoadedFile != null)
              ? _buildChartView()
              : _buildWelcomeView(),
        ),
      ],
    );
  }

  Widget _buildMlPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'ML Tools',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '1. Train Model',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Tooltip(
                    message:
                        'How big of a step the model takes during each training iteration. Smaller values are slower but more precise.',
                    child: TextField(
                      controller: _learningRateController,
                      decoration: const InputDecoration(
                        labelText: 'Learning Rate',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Tooltip(
                    message:
                        'How many times the model looks at the data to learn. More iterations can improve accuracy but take longer.',
                    child: TextField(
                      controller: _iterationsController,
                      decoration: const InputDecoration(
                        labelText: 'Training Iterations',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.model_training),
                      label: const Text('Train on Current File'),
                      onPressed: () => _runTraining(trainOnAllFiles: false),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.folder_copy_outlined),
                      label: const Text('Train on All Project Files'),
                      onPressed: () => _runTraining(trainOnAllFiles: true),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text(
                    '2. Auto-Label by Threshold',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add labels if > ${(_autoLabelAddThreshold * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Slider(
                    value: _autoLabelAddThreshold,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    label:
                        '${(_autoLabelAddThreshold * 100).toStringAsFixed(0)}%',
                    onChanged: (value) {
                      setState(() {
                        // Ensure Add threshold is always >= Remove threshold
                        _autoLabelAddThreshold = max(
                          value,
                          _autoLabelRemoveThreshold,
                        );
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Remove labels if < ${(_autoLabelRemoveThreshold * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  Slider(
                    activeColor: Theme.of(context).colorScheme.error,
                    value: _autoLabelRemoveThreshold,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    label:
                        '${(_autoLabelRemoveThreshold * 100).toStringAsFixed(0)}%',
                    onChanged: (value) {
                      setState(() {
                        // Ensure Remove threshold is always <= Add threshold
                        _autoLabelRemoveThreshold = min(
                          value,
                          _autoLabelAddThreshold,
                        );
                      });
                    },
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.auto_fix_high),
                      label: const Text('Apply Auto-Labels'),
                      onPressed: _similarityScores == null
                          ? null
                          : _applyAutoLabels,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWelcomeView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.folder_open, size: 80, color: Colors.grey),
          const SizedBox(height: 20),
          const Text('Select a project folder to begin.'),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: const Icon(Icons.folder),
            label: const Text('Choose Folder'),
            onPressed: _pickProjectFolder,
          ),
        ],
      ),
    );
  }

  Widget _buildExplorerView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 16.0, 8.0, 16.0),
          child: Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: _projectFolderPath ?? 'No project folder selected',
                  child: Text(
                    'Project: ${p.basename(_projectFolderPath ?? "None")}',
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.folder_open),
                onPressed: _pickProjectFolder,
                tooltip: 'Change Project Folder',
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _csvFilesInProject.isEmpty
              ? const Center(child: Text('No .csv files found in this folder.'))
              : ListView.builder(
                  itemCount: _csvFilesInProject.length,
                  itemBuilder: (context, index) {
                    final file = _csvFilesInProject[index];
                    return ListTile(
                      title: Text(p.basename(file.path)),
                      leading: const Icon(Icons.description_outlined),
                      onTap: () => _loadFile(file as File),
                      selected: _currentlyLoadedFile?.path == file.path,
                      selectedTileColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildColumnSelectorPanel() {
    if (_fullCsvHeaders == null) {
      return const Center(child: Text("Load a file first."));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Select Columns',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: _fullCsvHeaders!.length,
            itemBuilder: (context, index) {
              return CheckboxListTile(
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(_fullCsvHeaders![index]),
                value: _tempSelectedColumnIndices.contains(index),
                onChanged: (isSelected) {
                  setState(() {
                    if (isSelected == true) {
                      _tempSelectedColumnIndices.add(index);
                    } else {
                      _tempSelectedColumnIndices.remove(index);
                    }
                  });
                },
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () =>
                    setState(() => _isColumnSelectorVisible = false),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  _applyColumnSelection(Set.from(_tempSelectedColumnIndices));
                  setState(() => _isColumnSelectorVisible = false);
                },
                child: const Text('Apply'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChartView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      value: _labelColumnIndex,
                      hint: const Text('Choose Label Column'),
                      items:
                          _filteredCsvHeaders
                              ?.asMap()
                              .entries
                              .map(
                                (entry) => DropdownMenuItem<int>(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ),
                              )
                              .toList() ??
                          [],
                      onChanged: _updateLabelColumn,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButton<dynamic>(
                      isExpanded: true,
                      value: _selectedLabelValue,
                      hint: const Text('Select Label Value'),
                      items: _labelColumnIndex == null
                          ? []
                          : _uniqueValuesInLabelColumn
                                .map(
                                  (value) => DropdownMenuItem<dynamic>(
                                    value: value,
                                    child: Text(value.toString()),
                                  ),
                                )
                                .toList(),
                      onChanged: (newValue) => setState(() {
                        _selectedLabelValue = newValue;
                        _similarityScores = null;
                        _lastUsedFeatureIndices = null;
                        _chartData = _prepareChartData(_filteredCsvData!);
                        _originalChartData = _prepareChartData(
                          _filteredCsvData!,
                        );
                      }),
                    ),
                  ),
                ],
              ),
              DropdownButton<ChartType>(
                isExpanded: true,
                value: _selectedChartType,
                hint: const Text('Select Chart Type'),
                items: const [
                  DropdownMenuItem(
                    value: ChartType.line,
                    child: Text('Line Chart'),
                  ),
                  DropdownMenuItem(
                    value: ChartType.spline,
                    child: Text('Spline Chart (Smooth)'),
                  ),
                  DropdownMenuItem(
                    value: ChartType.stepLine,
                    child: Text('Step Line Chart'),
                  ),
                ],
                onChanged: (newType) async {
                  if (newType != null) await _showLineWidthDialog(newType);
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: (_filteredCsvData == null)
              ? const Center(
                  child: Text('Select columns to display the chart.'),
                )
              : SfCartesianChart(
                  primaryXAxis: const NumericAxis(
                    title: AxisTitle(text: 'Sample Index'),
                  ),
                  primaryYAxis: const NumericAxis(
                    title: AxisTitle(text: 'Sensor Value'),
                  ),
                  axes: const <ChartAxis>[
                    NumericAxis(
                      name: 'eventAxis',
                      opposedPosition: true,
                      title: AxisTitle(text: 'Events'),
                      minimum: 0,
                      maximum: 1.2,
                      interval: 1,
                    ),
                    NumericAxis(
                      name: 'similarityAxis',
                      opposedPosition: true,
                      title: AxisTitle(text: 'Probability'),
                      minimum: 0,
                      maximum: 1.05,
                      interval: 0.25,
                      majorGridLines: MajorGridLines(width: 0),
                    ),
                  ],
                  legend: const Legend(
                    isVisible: true,
                    position: LegendPosition.bottom,
                  ),
                  tooltipBehavior: TooltipBehavior(
                    enable: true,
                    format: 'series.name : point.y',
                  ),
                  zoomPanBehavior: _zoomPanBehavior,
                  series: _createSeries(),
                ),
        ),
      ],
    );
  }
}

class ChartData {
  final int index;
  dynamic label;
  final List<dynamic> values;

  ChartData({required this.index, this.label, required this.values});

  ChartData.from(ChartData other)
    : index = other.index,
      label = other.label,
      values = List.from(other.values);
}
