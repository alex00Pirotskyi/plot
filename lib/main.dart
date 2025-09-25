import 'dart:convert';
import 'dart:io';
import 'package:charts_app/tree_classifier.dart'; // Only tree classifier is needed
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
  int? _activePanelIndex;

  // State for Auto-Labeling
  double _autoLabelAddThreshold = 0.8;
  double _autoLabelRemoveThreshold = 0.4;

  // Project and File State
  String? _projectFolderPath;
  List<FileSystemEntity> _csvFilesInProject = [];
  File? _currentlyLoadedFile;

  // CSV Data State
  List<List<dynamic>>? _fullCsvData;
  List<String>? _fullCsvHeaders;
  List<List<dynamic>>? _filteredCsvData;
  List<String>? _filteredCsvHeaders;

  // Column Selection
  final Set<int> _tempSelectedColumnIndices = <int>{};

  // Chart Data State
  late List<ChartData> _chartData = [];
  late List<ChartData> _originalChartData = [];

  // Chart Display Preferences
  bool _showMarkers = false;
  ChartType _selectedChartType = ChartType.line;
  double _lineWidth = 1.5;
  double _markerWidth = 4.0;
  double _markerHeight = 4.0;

  // Editing State
  bool _isEditMode = false;
  int? _labelColumnIndex;
  List<dynamic> _uniqueValuesInLabelColumn = [];
  dynamic _selectedLabelValue;

  // --- REFACTORED ML STATE (TREE-ONLY) ---
  String? _treeFolderPath;
  List<FileSystemEntity> _treeFilesInFolder = [];
  TreeEnsembleClassifier? _treeModel;
  List<double>? _treeProbabilities;
  bool _showProbabilities = true;

  // Chart Behavior
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

    _loadInitialFolder().then((loaded) {
      if (loaded) {
        setState(() => _activePanelIndex = 0);
      }
    });
    _loadPreferences();
  }

  // === UI HELPER METHODS ===
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
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  title.toLowerCase().contains('delete') ||
                      title.toLowerCase().contains('reset')
                  ? Theme.of(context).colorScheme.error
                  : null,
              foregroundColor:
                  title.toLowerCase().contains('delete') ||
                      title.toLowerCase().contains('reset')
                  ? Theme.of(context).colorScheme.onError
                  : null,
            ),
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
        _activePanelIndex = 0;
      });
      _loadCsvFilesInFolder();
    }
  }

  Future<bool> _loadInitialFolder() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString('project_folder_path');
    if (savedPath != null) {
      setState(() => _projectFolderPath = savedPath);
      await _loadCsvFilesInFolder();
      return true;
    }
    return false;
  }

  Future<void> _loadCsvFilesInFolder() async {
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
          _treeModel = null;
          _treeProbabilities = null;
          _isEditMode = false;
          _activePanelIndex = null;
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
      _treeModel = null;
      _treeProbabilities = null;
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
          _treeModel = null;
          _treeProbabilities = null;
          _chartData = [];
          _originalChartData = [];
          _activePanelIndex = 0;
        });
        _loadCsvFilesInFolder();
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
    _loadCsvFilesInFolder();
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

  void _resetChartEdits() async {
    final confirm = await _showConfirmationDialog(
      title: "Reset Edits?",
      content:
          "Are you sure you want to discard all labeling changes for this file?",
    );
    if (confirm != true) return;

    setState(() {
      _chartData = _originalChartData.map((d) => ChartData.from(d)).toList();
      _treeProbabilities = null;
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

  // === ML & DIALOGS (REFACTORED FOR TREE MODELS) ===
  Future<void> _pickTreeFolder() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      setState(() {
        _treeFolderPath = selectedDirectory;
      });
      _loadTreeFilesInFolder();
    }
  }

  Future<void> _loadTreeFilesInFolder() async {
    if (_treeFolderPath == null) return;
    try {
      final dir = Directory(_treeFolderPath!);
      final files = await dir
          .list()
          .where((item) => item.path.toLowerCase().endsWith('.json'))
          .toList();
      setState(() {
        _treeFilesInFolder = files..sort((a, b) => a.path.compareTo(b.path));
      });
    } catch (e) {
      _showSnackbar('Error reading tree folder: $e', isError: true);
    }
  }

  Future<void> _loadTreeModel(File file) async {
    final model = await TreeEnsembleClassifier.fromFile(file);

    if (model == null) {
      _showSnackbar('Failed to load or parse the tree model.', isError: true);
      return;
    }

    final modelFeatures = model.featureNames.toSet();
    final csvHeaders = _fullCsvHeaders?.toSet();

    if (csvHeaders == null) {
      _showSnackbar('Load a CSV file before loading a model.', isError: true);
      return;
    }

    if (!csvHeaders.containsAll(modelFeatures)) {
      final missingFeatures = modelFeatures.difference(csvHeaders);
      _showSnackbar(
        'Incompatible Tree: Missing features in CSV: ${missingFeatures.join(', ')}',
        isError: true,
      );
      return;
    }

    setState(() {
      _treeModel = model;
    });

    _showSnackbar('Tree model loaded successfully: ${p.basename(file.path)}');
    _runTreePrediction();
  }

  void _runTreePrediction() {
    if (_treeModel == null || _fullCsvData == null) {
      _showSnackbar('Load a tree model and CSV data first.', isError: true);
      return;
    }

    final probabilities = <double>[];
    final int expectedColumnCount = _fullCsvHeaders!.length;

    for (final row in _fullCsvData!) {
      try {
        List<double> fullFeatureRow = List.generate(expectedColumnCount, (i) {
          if (i >= row.length) {
            return 0.0;
          }
          final value = row[i];
          return (value is num) ? value.toDouble() : 0.0;
        }, growable: false);

        final proba = _treeModel!.predict(fullFeatureRow);
        probabilities.add(proba);
      } catch (e) {
        probabilities.add(0.0);
        debugPrint('Could not process row due to an unexpected error: $e');
      }
    }

    setState(() {
      _treeProbabilities = probabilities;
    });

    _showSnackbar('Tree model prediction complete.');
  }

  void _applyAutoLabels() async {
    if (_treeProbabilities == null) {
      _showSnackbar("You must run a model first!", isError: true);
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
        if (i >= _treeProbabilities!.length) continue;
        final score = _treeProbabilities![i];
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

  Future<void> _showLineWidthDialog() async {
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

    if (_showProbabilities && _treeProbabilities != null) {
      series.add(
        LineSeries<double, int>(
          dataSource: _treeProbabilities!,
          xValueMapper: (score, index) => index,
          yValueMapper: (score, _) => score,
          name: 'Tree Probability',
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
            selectedIndex: _activePanelIndex,
            onDestinationSelected: (index) {
              setState(() {
                if (_activePanelIndex == index) {
                  _activePanelIndex = null;
                } else {
                  _activePanelIndex = index;
                  if (index == 1 && _fullCsvData != null) {
                    _tempSelectedColumnIndices.clear();
                    if (_filteredCsvHeaders != null) {
                      for (final header in _filteredCsvHeaders!) {
                        int idx = _fullCsvHeaders!.indexOf(header);
                        if (idx != -1) _tempSelectedColumnIndices.add(idx);
                      }
                    }
                  }
                }
              });
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
                disabled: _currentlyLoadedFile == null,
                label: const Text('ML Tools'),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.save_outlined),
                disabled: _chartData.isEmpty,
                label: const Text("File"),
              ),
              NavigationRailDestination(
                icon: Icon(
                  _isEditMode ? Icons.edit_off_outlined : Icons.edit_outlined,
                ),
                disabled: _chartData.isEmpty,
                label: const Text("Edit"),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.search),
                disabled: _chartData.isEmpty,
                label: const Text("Zoom"),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.tune_outlined),
                disabled: _chartData.isEmpty,
                label: const Text('Plot Settings'),
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
    final panelBuilders = {
      0: _buildExplorerView,
      1: _buildColumnSelectorPanel,
      2: _buildMlPanel,
      3: _buildFilePanel,
      4: _buildEditPanel,
      5: _buildZoomPanel,
      6: _buildPlotSettingsPanel,
    };

    final activePanelBuilder = panelBuilders[_activePanelIndex];

    return Row(
      children: [
        if (activePanelBuilder != null)
          SizedBox(width: 300, child: activePanelBuilder()),
        if (activePanelBuilder != null) const VerticalDivider(width: 1),
        Expanded(
          child: (_currentlyLoadedFile != null)
              ? _buildChartView()
              : _buildWelcomeView(),
        ),
      ],
    );
  }

  // --- SIDE PANELS ---

  Widget _buildFilePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'File Options',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              ListTile(
                leading: const Icon(Icons.save),
                title: const Text('Save'),
                onTap: () => _saveFile(asNew: false),
              ),
              ListTile(
                leading: const Icon(Icons.save_as),
                title: const Text('Save As...'),
                onTap: () => _saveFile(asNew: true),
              ),
              const Divider(),
              ListTile(
                leading: Icon(
                  Icons.delete_forever,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Delete File',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: _deleteCurrentFile,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEditPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Editing Tools',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const Divider(height: 1),
        ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(8),
          children: [
            SwitchListTile(
              secondary: Icon(_isEditMode ? Icons.edit_off : Icons.edit),
              title: const Text('Enable Edit Mode'),
              value: _isEditMode,
              onChanged: (value) => setState(() => _isEditMode = value),
            ),
            const Divider(),
            ListTile(
              leading: Icon(
                Icons.restore,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Reset All Edits',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: _resetChartEdits,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildZoomPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Zoom Controls',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              ListTile(
                leading: const Icon(Icons.zoom_in),
                title: const Text('Zoom In'),
                onTap: () => _zoomPanBehavior.zoomIn(),
              ),
              ListTile(
                leading: const Icon(Icons.zoom_out),
                title: const Text('Zoom Out'),
                onTap: () => _zoomPanBehavior.zoomOut(),
              ),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Reset Zoom'),
                onTap: () => _zoomPanBehavior.reset(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlotSettingsPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Plot Settings',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Chart Type',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              SegmentedButton<ChartType>(
                segments: const [
                  ButtonSegment(
                    value: ChartType.line,
                    label: Text('Line'),
                    icon: Icon(Icons.show_chart),
                  ),
                  ButtonSegment(
                    value: ChartType.spline,
                    label: Text('Spline'),
                    icon: Icon(Icons.gesture),
                  ),
                  ButtonSegment(
                    value: ChartType.stepLine,
                    label: Text('Step'),
                    icon: Icon(Icons.stairs),
                  ),
                ],
                selected: {_selectedChartType},
                onSelectionChanged: (newSelection) {
                  setState(() => _selectedChartType = newSelection.first);
                  _savePreferences();
                },
              ),
              const Divider(height: 24),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Line Width'),
                subtitle: Text(_lineWidth.toStringAsFixed(1)),
                trailing: IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: _showLineWidthDialog,
                ),
              ),
              Slider(
                value: _lineWidth,
                min: 0.5,
                max: 5.0,
                divisions: 9,
                label: _lineWidth.toStringAsFixed(1),
                onChanged: (value) {
                  setState(() => _lineWidth = value);
                },
                onChangeEnd: (value) => _savePreferences(),
              ),
              const Divider(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show Markers'),
                value: _showMarkers,
                onChanged: (value) {
                  setState(() => _showMarkers = value);
                  _savePreferences();
                },
              ),
              if (_showMarkers) ...[
                const SizedBox(height: 8),
                Text('Marker Width: ${_markerWidth.toStringAsFixed(1)}'),
                Slider(
                  value: _markerWidth,
                  min: 1,
                  max: 20,
                  divisions: 19,
                  label: _markerWidth.toStringAsFixed(1),
                  onChanged: (value) => setState(() => _markerWidth = value),
                  onChangeEnd: (value) => _savePreferences(),
                ),
                Text('Marker Height: ${_markerHeight.toStringAsFixed(1)}'),
                Slider(
                  value: _markerHeight,
                  min: 1,
                  max: 20,
                  divisions: 19,
                  label: _markerHeight.toStringAsFixed(1),
                  onChanged: (value) => setState(() => _markerHeight = value),
                  onChangeEnd: (value) => _savePreferences(),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMlPanel() {
    final bool canAutoLabel =
        _labelColumnIndex != null &&
        _selectedLabelValue != null &&
        _treeProbabilities != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Tree Model Tools',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              ExpansionTile(
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Tree Models'),
                    Tooltip(
                      message: 'Select folder containing .json models',
                      child: IconButton(
                        icon: const Icon(Icons.folder_open_outlined),
                        onPressed: _pickTreeFolder,
                      ),
                    ),
                  ],
                ),
                initiallyExpanded: true,
                children: [
                  if (_treeFilesInFolder.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text(
                        'No folder selected or no .json files found.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _treeFilesInFolder.length,
                        itemBuilder: (context, index) {
                          final file = _treeFilesInFolder[index];
                          return ListTile(
                            leading: const Icon(Icons.insights),
                            title: Text(
                              p.basename(file.path),
                              overflow: TextOverflow.ellipsis,
                            ),
                            selected: _treeModel?.sourcePath == file.path,
                            onTap: () => _loadTreeModel(file as File),
                          );
                        },
                      ),
                    ),
                ],
              ),
              const Divider(height: 24),
              if (_treeModel != null)
                ExpansionTile(
                  title: const Text('Model Metadata'),
                  children: _treeModel!.meta.entries.map((entry) {
                    return ListTile(
                      title: Text(entry.key),
                      subtitle: Text(entry.value.toString()),
                      dense: true,
                    );
                  }).toList(),
                ),
              if (_treeModel != null) const Divider(height: 24),
              Text("Controls", style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Show Probabilities'),
                value: _showProbabilities,
                onChanged: _treeProbabilities == null
                    ? null
                    : (value) {
                        setState(() => _showProbabilities = value);
                      },
              ),
              const SizedBox(height: 16),
              Text(
                'Add labels if > ${(_autoLabelAddThreshold * 100).toStringAsFixed(0)}%',
              ),
              Slider(
                value: _autoLabelAddThreshold,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                label: '${(_autoLabelAddThreshold * 100).toStringAsFixed(0)}%',
                onChanged: !canAutoLabel
                    ? null
                    : (value) {
                        setState(() {
                          _autoLabelAddThreshold = value;
                          if (_autoLabelRemoveThreshold > value) {
                            _autoLabelRemoveThreshold = value;
                          }
                        });
                      },
              ),
              Text(
                'Remove labels if < ${(_autoLabelRemoveThreshold * 100).toStringAsFixed(0)}%',
              ),
              Slider(
                value: _autoLabelRemoveThreshold,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                label:
                    '${(_autoLabelRemoveThreshold * 100).toStringAsFixed(0)}%',
                onChanged: !canAutoLabel
                    ? null
                    : (value) {
                        setState(() {
                          _autoLabelRemoveThreshold = value;
                          if (_autoLabelAddThreshold < value) {
                            _autoLabelAddThreshold = value;
                          }
                        });
                      },
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Apply Auto-Labels'),
                onPressed: canAutoLabel ? _applyAutoLabels : null,
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                icon: const Icon(Icons.restore),
                label: const Text('Revert All Changes'),
                onPressed: _resetChartEdits,
              ),
            ],
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    style: Theme.of(context).textTheme.titleLarge,
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Select Columns',
            style: Theme.of(context).textTheme.titleLarge,
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
                onPressed: () => setState(() => _activePanelIndex = null),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  _applyColumnSelection(Set.from(_tempSelectedColumnIndices));
                  setState(() => _activePanelIndex = null);
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
          child: Row(
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
                    _treeProbabilities = null;
                    _chartData = _prepareChartData(_filteredCsvData!);
                    _originalChartData = _prepareChartData(_filteredCsvData!);
                  }),
                ),
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
