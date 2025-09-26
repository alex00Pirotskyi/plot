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

enum LabelSource { fromSettings, fromCsv }

class ChartViewerPage extends StatefulWidget {
  const ChartViewerPage({super.key});
  @override
  State<ChartViewerPage> createState() => _ChartViewerPageState();
}

class _ChartViewerPageState extends State<ChartViewerPage> {
  // === STATE VARIABLES ===
  int? _activePanelIndex;
  double _panelWidth = 350.0;

  // State for Auto-Labeling
  double _autoLabelAddThreshold = 0.8;
  double _autoLabelRemoveThreshold = 0.4;

  // Project and File State
  String? _projectFolderPath;
  List<FileSystemEntity> _csvFilesInProject = [];
  List<FileSystemEntity> _filteredCsvFilesInProject = [];
  File? _currentlyLoadedFile;
  final TextEditingController _projectFilterController =
      TextEditingController();

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
  bool _isNormalizationEnabled = false;
  double _normalizationPercentile = 1.0; // 1.0 for P100

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
  bool _probabilityChartTypeIsBar = false; // false = Line, true = Bar
  double _probabilityOpacity = 0.7;

  // === NEW: State for Label Settings ===
  Map<String, dynamic>? _labelSettings;
  final Set<String> _selectedActiveLabels = <String>{};

  // Chart Behavior
  late ZoomPanBehavior _zoomPanBehavior;

  // === PREFERENCE KEYS ===
  static const String _projectFolderPathKey = 'project_folder_path';
  static const String _treeFolderPathKey = 'tree_folder_path';
  static const String _lastCsvFileKey = 'last_csv_file_path';
  static const String _lastModelFileKey = 'last_model_file_path';
  static const String _globalSelectedColumnsKey = 'global_selected_columns_v1';
  static const String _labelSettingsKey = 'label_settings_json_v1';
  static const String _selectedActiveLabelsKey = 'selected_active_labels_v1';
  static const String _showLabelsKey = 'show_labels_v1';

  // State for choosing the label source
  LabelSource _activeLabelSource = LabelSource.fromCsv;
  bool _showLabels = true;

  @override
  void initState() {
    super.initState();
    _zoomPanBehavior = ZoomPanBehavior(
      enablePinching: true,
      enablePanning: true,
      enableSelectionZooming: true,
    );

    _projectFilterController.addListener(_filterProjectFiles);
    _initializeApplication();
  }

  @override
  void dispose() {
    _projectFilterController.dispose();
    super.dispose();
  }

  Future<void> _initializeApplication() async {
    await _loadPreferences();
    bool folderLoaded = await _loadInitialFolder();
    if (folderLoaded) {
      await _loadLastSession();
      setState(() => _activePanelIndex = 0);
    }
    if (_labelSettings != null) {
      _applyLoadedLabelSettings();
    }
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

  // === REFACTORED HELPER ===
  bool _isDestructiveAction(String title) {
    final lowerTitle = title.toLowerCase();
    return lowerTitle.contains('delete') ||
        lowerTitle.contains('reset') ||
        lowerTitle.contains('overwrite');
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
              backgroundColor: _isDestructiveAction(title)
                  ? Theme.of(context).colorScheme.error
                  : null,
              foregroundColor: _isDestructiveAction(title)
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
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
      initialDirectory: _projectFolderPath,
    );
    if (selectedDirectory != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_projectFolderPathKey, selectedDirectory);
      setState(() {
        _projectFolderPath = selectedDirectory;
        _activePanelIndex = 0;
      });
      await _loadCsvFilesInFolder();
    }
  }

  Future<bool> _loadInitialFolder() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString(_projectFolderPathKey);
    if (savedPath != null) {
      setState(() => _projectFolderPath = savedPath);
      await _loadCsvFilesInFolder();
      return true;
    }
    return false;
  }

  void _filterProjectFiles() {
    final filterText = _projectFilterController.text.toLowerCase();
    setState(() {
      _filteredCsvFilesInProject = _csvFilesInProject
          .where(
            (file) => p.basename(file.path).toLowerCase().contains(filterText),
          )
          .toList();
    });
  }

  Future<void> _loadCsvFilesInFolder() async {
    if (_projectFolderPath == null) return;
    try {
      final dir = Directory(_projectFolderPath!);
      final files = await dir
          .list()
          .where((item) => item.path.toLowerCase().endsWith('.csv'))
          .toList();
      setState(() {
        _csvFilesInProject = files..sort((a, b) => a.path.compareTo(b.path));
        _filterProjectFiles();
      });
    } catch (e) {
      _showSnackbar(
        'Error reading folder: $e. Please choose a different folder.',
        isError: true,
      );
    }
  }

  Future<void> _loadFile(File file, {bool isFromSession = false}) async {
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
        });

        final prefs = await SharedPreferences.getInstance();
        if (!isFromSession) {
          await prefs.setString(_lastCsvFileKey, file.path);
          await prefs.remove(_lastModelFileKey);
        }

        final savedHeaders =
            prefs.getStringList(_globalSelectedColumnsKey) ?? [];
        final selectedIndices = <int>{};

        for (final header in savedHeaders) {
          int index = _fullCsvHeaders!.indexOf(header);
          if (index != -1) selectedIndices.add(index);
        }

        _applyColumnSelection(selectedIndices);
        if (_labelSettings != null &&
            _activeLabelSource == LabelSource.fromSettings) {
          _applyLoadedLabelSettings();
        }
      }
    } catch (e) {
      _showSnackbar('Error loading file: $e', isError: true);
    }
  }

  Future<void> _saveShowLabelsPreference() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showLabelsKey, _showLabels);
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
      _labelColumnIndex = null;
      _selectedLabelValue = null;
      _chartData = _prepareChartData(_filteredCsvData!);
      _originalChartData = _prepareChartData(_filteredCsvData!);
      _uniqueValuesInLabelColumn = [];
      _treeModel = null;
      _treeProbabilities = null;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_globalSelectedColumnsKey, newHeaders);

    if (_labelSettings != null) {
      final requiredColumn = _labelSettings!['labels']['column_name'] as String;
      if (!newHeaders.contains(requiredColumn) &&
          (_showLabels || _activeLabelSource == LabelSource.fromSettings)) {
        setState(() {
          _showLabels = false;
          _activeLabelSource = LabelSource.fromCsv;
        });
        await _saveShowLabelsPreference();
        _showSnackbar(
          'Labels turned off: Required column "$requiredColumn" was deselected.',
        );
      }
    }
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
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_lastCsvFileKey);
        await prefs.remove(_lastModelFileKey);

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
        await _loadCsvFilesInFolder();
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

    if (!asNew) {
      final confirm = await _showConfirmationDialog(
        title: 'Overwrite File?',
        content:
            'This will replace the original file. This action cannot be undone.',
      );
      if (confirm != true) return;
    }

    final editedFilteredData = _convertChartDataBackToFiltered();
    final List<List<dynamic>> fullReconstructedData = [_fullCsvHeaders!];

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
      filePath = p.join(
        _projectFolderPath!,
        '${originalName}_edited_$timestamp.csv',
      );
    }

    await File(filePath).writeAsString(csvString);
    _showSnackbar('File saved successfully to $filePath');
    await _loadCsvFilesInFolder();
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
        values: List.from(sourceData[i]),
      );
    });
  }

  void _resetChartEdits() async {
    final confirm = await _showConfirmationDialog(
      title: "Reset Edits?",
      content:
          "Are you sure you want to discard all labeling and normalization changes for this file?",
    );
    if (confirm != true) return;

    setState(() {
      _chartData = _originalChartData.map((d) => ChartData.from(d)).toList();
      _treeProbabilities = null;
      _isNormalizationEnabled = false;
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
    final previousValue = _selectedLabelValue;

    setState(() {
      _selectedLabelValue = null;
      _labelColumnIndex = newIndexInFilteredList;

      if (_activeLabelSource == LabelSource.fromCsv) {
        _uniqueValuesInLabelColumn = [];
        if (newIndexInFilteredList != null) {
          final uniqueValues = _filteredCsvData!
              .map((row) => row[newIndexInFilteredList])
              .toSet()
              .where((v) => v != null && v.toString().trim().isNotEmpty)
              .toList();
          _uniqueValuesInLabelColumn = uniqueValues;

          if (previousValue != null &&
              _uniqueValuesInLabelColumn.contains(previousValue)) {
            _selectedLabelValue = previousValue;
          } else if (_uniqueValuesInLabelColumn.isNotEmpty) {
            _selectedLabelValue = _uniqueValuesInLabelColumn.first;
          }
        }
      } else {
        // LabelSource.fromSettings
        final auto = _autoPickActiveLabelFromSettings();
        if (auto != null) {
          _selectedLabelValue = auto;
        } else if (_selectedActiveLabels.isNotEmpty && _labelSettings != null) {
          final labelValuesMap = (_labelSettings!['labels']['values'] as Map)
              .cast<String, dynamic>();
          _selectedLabelValue = _isLabelColumnNumeric()
              ? labelValuesMap[_selectedActiveLabels.first]
              : _selectedActiveLabels.first;
        } else {
          _selectedLabelValue = null;
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
      _treeFolderPath = prefs.getString(_treeFolderPathKey);
      _showLabels = prefs.getBool(_showLabelsKey) ?? true;

      final settingsJsonString = prefs.getString(_labelSettingsKey);
      if (settingsJsonString != null) {
        try {
          _labelSettings = json.decode(settingsJsonString);
          _activeLabelSource = LabelSource.fromSettings;
        } catch (e) {
          debugPrint("Error decoding label settings from prefs: $e");
          _labelSettings = null;
        }
      }
      final savedLabels = prefs.getStringList(_selectedActiveLabelsKey) ?? [];
      _selectedActiveLabels.clear();
      _selectedActiveLabels.addAll(savedLabels);

      if (_activeLabelSource == LabelSource.fromSettings &&
          _labelSettings != null) {
        _selectedLabelValue = null;
      }
    });
  }

  Future<void> _loadLastSession() async {
    final prefs = await SharedPreferences.getInstance();
    final csvPath = prefs.getString(_lastCsvFileKey);
    final modelPath = prefs.getString(_lastModelFileKey);

    if (csvPath != null) {
      final csvFile = File(csvPath);
      if (await csvFile.exists()) {
        await _loadFile(csvFile, isFromSession: true);

        if (modelPath != null) {
          final modelFile = File(modelPath);
          if (await modelFile.exists()) {
            await _loadTreeModel(modelFile, isFromSession: true);
          }
        }
      }
    }
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('chart_line_width', _lineWidth);
    await prefs.setDouble('chart_marker_width', _markerWidth);
    await prefs.setDouble('chart_marker_height', _markerHeight);
    await prefs.setBool('chart_show_markers', _showMarkers);
    await prefs.setInt('chart_type', _selectedChartType.index);
  }

  // === LABEL SETTINGS ===
  Future<void> _loadLabelSettings() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result != null && result.files.single.path != null) {
      try {
        final file = File(result.files.single.path!);
        final jsonString = await file.readAsString();
        final decodedJson = json.decode(jsonString);

        if (decodedJson is! Map ||
            decodedJson['labels'] is! Map ||
            decodedJson['labels']['column_name'] is! String ||
            decodedJson['labels']['values'] is! Map) {
          _showSnackbar('Invalid JSON format.', isError: true);
          return;
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_labelSettingsKey, jsonString);

        setState(() {
          _labelSettings = decodedJson as Map<String, dynamic>;
          final labelValuesMap = (_labelSettings!['labels']['values'] as Map);
          _selectedActiveLabels.clear();
          _selectedActiveLabels.addAll(labelValuesMap.keys.cast<String>());
          _activeLabelSource = LabelSource.fromSettings;

          final auto = _autoPickActiveLabelFromSettings();
          if (auto != null) {
            _selectedLabelValue = auto;
          } else if (_selectedActiveLabels.isNotEmpty) {
            _selectedLabelValue = _isLabelColumnNumeric()
                ? labelValuesMap[_selectedActiveLabels.first]
                : _selectedActiveLabels.first;
          } else {
            _selectedLabelValue = null;
          }
        });

        await _saveActiveLabelSelection();
        _applyLoadedLabelSettings();
        _showSnackbar('Label settings loaded and saved successfully.');
      } catch (e) {
        _showSnackbar('Error reading/parsing settings file: $e', isError: true);
      }
    }
  }

  void _applyLoadedLabelSettings() {
    if (_labelSettings == null || _filteredCsvHeaders == null) return;

    final String columnName = _labelSettings!['labels']['column_name'];
    final int targetIndex = _filteredCsvHeaders!.indexOf(columnName);

    if (targetIndex != -1) {
      _updateLabelColumn(targetIndex);
    } else {
      _showSnackbar(
        'Label column "$columnName" not found in selected CSV columns.',
        isError: true,
      );
    }
  }

  Future<void> _saveActiveLabelSelection() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _selectedActiveLabelsKey,
      _selectedActiveLabels.toList(),
    );
  }

  // === ML & DIALOGS ===
  Future<void> _pickTreeFolder() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
      initialDirectory: _treeFolderPath,
    );
    if (selectedDirectory != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_treeFolderPathKey, selectedDirectory);
      setState(() => _treeFolderPath = selectedDirectory);
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

  Future<void> _loadTreeModel(File file, {bool isFromSession = false}) async {
    final model = await TreeEnsembleClassifier.fromFile(file);
    if (model == null) {
      _showSnackbar('Failed to load or parse the tree model.', isError: true);
      return;
    }

    final csvHeaders = _fullCsvHeaders?.toSet();
    if (csvHeaders == null) {
      _showSnackbar('Load a CSV file before loading a model.', isError: true);
      return;
    }

    final modelFeatures = model.featureNames.toSet();
    if (!csvHeaders.containsAll(modelFeatures)) {
      final missingFeatures = modelFeatures.difference(csvHeaders);
      _showSnackbar(
        'Incompatible Tree: Missing features in CSV: ${missingFeatures.join(', ')}',
        isError: true,
      );
      return;
    }

    if (!isFromSession) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastModelFileKey, file.path);
    }

    setState(() => _treeModel = model);
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
          if (i >= row.length) return 0.0;
          final value = row[i];
          return (value is num) ? value.toDouble() : 0.0;
        }, growable: false);
        probabilities.add(_treeModel!.predict(fullFeatureRow));
      } catch (e) {
        probabilities.add(0.0);
        debugPrint('Could not process row due to an unexpected error: $e');
      }
    }
    setState(() => _treeProbabilities = probabilities);
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
          'This will add labels above ${(_autoLabelAddThreshold * 100).toStringAsFixed(0)}% and remove labels below ${(_autoLabelRemoveThreshold * 100).toStringAsFixed(0)}%. This action is permanent until reset.',
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
      setState(() => _lineWidth = newWidth);
      await _savePreferences();
    }
  }

  bool _isLabelColumnNumeric() {
    if (_filteredCsvData == null || _labelColumnIndex == null) return true;
    for (final row in _filteredCsvData!) {
      final v = row[_labelColumnIndex!];
      if (v != null) return v is num;
    }
    return true;
  }

  dynamic _autoPickActiveLabelFromSettings() {
    if (_labelSettings == null ||
        _filteredCsvData == null ||
        _labelColumnIndex == null) {
      return null;
    }

    final Map<String, dynamic> labelValuesMap =
        (_labelSettings!['labels']['values'] as Map).cast<String, dynamic>();
    final selectedNames = _selectedActiveLabels.toSet();
    if (selectedNames.isEmpty) return null;

    final bool numericCol = _isLabelColumnNumeric();
    final Map<dynamic, int> counts = {};

    for (final row in _filteredCsvData!) {
      final v = row[_labelColumnIndex!];
      if (v == null) continue;

      if (numericCol) {
        for (final name in selectedNames) {
          final mapped = labelValuesMap[name];
          if (mapped == v) {
            counts[mapped] = (counts[mapped] ?? 0) + 1;
          }
        }
      } else if (v is String && selectedNames.contains(v)) {
        counts[v] = (counts[v] ?? 0) + 1;
      }
    }

    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  // === CHART SERIES CREATION ===
  List<CartesianSeries<dynamic, int>> _createSeries() {
    if (_filteredCsvHeaders == null) return [];

    List<ChartData> dataSource = _chartData;

    if (_isNormalizationEnabled) {
      final Map<int, double> maxValues = {};
      final numericColumnIndices = <int>{};

      for (int i = 0; i < _filteredCsvHeaders!.length; i++) {
        if (i == _labelColumnIndex) continue;
        if (_chartData.isNotEmpty && _chartData.first.values[i] is num) {
          numericColumnIndices.add(i);
          double maxVal = 0.0;
          for (final dataPoint in _chartData) {
            final val = dataPoint.values[i];
            if (val is num && val.abs() > maxVal) {
              maxVal = val.abs().toDouble();
            }
          }
          maxValues[i] = maxVal;
        }
      }

      dataSource = _chartData.map((dataPoint) {
        final newValues = List.from(dataPoint.values);
        for (int colIdx in numericColumnIndices) {
          final maxVal = maxValues[colIdx]!;
          final targetMax = maxVal * _normalizationPercentile;
          if (targetMax > 0 && newValues[colIdx] is num) {
            newValues[colIdx] = newValues[colIdx] / targetMax;
          }
        }
        return ChartData(
          index: dataPoint.index,
          label: dataPoint.label,
          values: newValues,
        );
      }).toList();
    }

    List<CartesianSeries<dynamic, int>> series = [];

    if (_showLabels &&
        _labelColumnIndex != null &&
        _selectedLabelValue != null) {
      series.add(
        ColumnSeries<ChartData, int>(
          dataSource: dataSource,
          xValueMapper: (d, _) => d.index,
          yValueMapper: (d, _) => d.label != null ? 1 : 0,
          name: 'Event: $_selectedLabelValue',
          yAxisName: 'eventAxis',
          width: 1,
          onPointTap: _editDataPoint,
          animationDuration: 0, // <-- Add this line
        ),
      );
    }

    for (int i = 0; i < _filteredCsvHeaders!.length; i++) {
      if (i == _labelColumnIndex) continue;
      series.add(_getSeriesType(i, _filteredCsvHeaders![i], dataSource));
    }

    if (_showProbabilities && _treeProbabilities != null) {
      if (_probabilityChartTypeIsBar) {
        series.add(
          ColumnSeries<double, int>(
            dataSource: _treeProbabilities!,
            xValueMapper: (score, index) => index,
            yValueMapper: (score, _) => score,
            name: 'Tree Probability',
            yAxisName: 'similarityAxis',
            color: Colors.green.withOpacity(_probabilityOpacity),
            width: 1,
          ),
        );
      } else {
        series.add(
          LineSeries<double, int>(
            dataSource: _treeProbabilities!,
            xValueMapper: (score, index) => index,
            yValueMapper: (score, _) => score,
            name: 'Tree Probability',
            yAxisName: 'similarityAxis',
            color: Colors.green.withOpacity(_probabilityOpacity),
            width: 2,
            dashArray: const <double>[5, 5],
          ),
        );
      }
    }
    return series;
  }

  // === REFACTORED METHOD ===
  // This method is now much cleaner, defining common properties only once
  // and using the switch statement just to select the series class.
  CartesianSeries<ChartData, int> _getSeriesType(
    int index,
    String header,
    List<ChartData> dataSource,
  ) {
    final ChartValueMapper<ChartData, int> xValueMapper = (d, _) => d.index;
    final ChartValueMapper<ChartData, num> yValueMapper = (d, _) {
      final val = d.values[index];
      return (val is num) ? val.toDouble() : 0.0;
    };
    final MarkerSettings markerSettings = _showMarkers
        ? MarkerSettings(
            isVisible: true,
            height: _markerHeight,
            width: _markerWidth,
          )
        : const MarkerSettings(isVisible: false);

    final seriesProps = {
      'name': header,
      'dataSource': dataSource,
      'xValueMapper': xValueMapper,
      'yValueMapper': yValueMapper,
      'width': _lineWidth,
      'onPointTap': _editDataPoint,
      'markerSettings': markerSettings,
      'animationDuration': 0.0,
    };

    switch (_selectedChartType) {
      case ChartType.spline:
        return SplineSeries<ChartData, int>(
          name: seriesProps['name'] as String,
          dataSource: seriesProps['dataSource'] as List<ChartData>,
          xValueMapper:
              seriesProps['xValueMapper'] as ChartValueMapper<ChartData, int>,
          yValueMapper:
              seriesProps['yValueMapper'] as ChartValueMapper<ChartData, num>,
          width: seriesProps['width'] as double,
          onPointTap:
              seriesProps['onPointTap'] as ChartPointInteractionCallback,
          markerSettings: seriesProps['markerSettings'] as MarkerSettings,
          animationDuration: seriesProps['animationDuration'] as double,
        );
      case ChartType.stepLine:
        return StepLineSeries<ChartData, int>(
          name: seriesProps['name'] as String,
          dataSource: seriesProps['dataSource'] as List<ChartData>,
          xValueMapper:
              seriesProps['xValueMapper'] as ChartValueMapper<ChartData, int>,
          yValueMapper:
              seriesProps['yValueMapper'] as ChartValueMapper<ChartData, num>,
          width: seriesProps['width'] as double,
          onPointTap:
              seriesProps['onPointTap'] as ChartPointInteractionCallback,
          markerSettings: seriesProps['markerSettings'] as MarkerSettings,
          animationDuration: seriesProps['animationDuration'] as double,
        );
      default: // ChartType.line
        return LineSeries<ChartData, int>(
          name: seriesProps['name'] as String,
          dataSource: seriesProps['dataSource'] as List<ChartData>,
          xValueMapper:
              seriesProps['xValueMapper'] as ChartValueMapper<ChartData, int>,
          yValueMapper:
              seriesProps['yValueMapper'] as ChartValueMapper<ChartData, num>,
          width: seriesProps['width'] as double,
          onPointTap:
              seriesProps['onPointTap'] as ChartPointInteractionCallback,
          markerSettings: seriesProps['markerSettings'] as MarkerSettings,
          animationDuration: seriesProps['animationDuration'] as double,
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
                icon: const Icon(Icons.label_outline),
                disabled: _fullCsvData == null,
                label: const Text('Labels'),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.computer),
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
                icon: const Icon(Icons.equalizer),
                disabled: _chartData.isEmpty,
                label: const Text("Normalize"),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.search),
                disabled: _chartData.isEmpty,
                label: const Text("Zoom"),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.tune_outlined),
                disabled: _chartData.isEmpty,
                label: const Text('Plot'),
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
      2: _buildLabelPanel,
      3: _buildMlPanel,
      4: _buildFilePanel,
      5: _buildEditPanel,
      6: _buildNormalizePanel,
      7: _buildZoomPanel,
      8: _buildPlotSettingsPanel,
    };
    final activePanelBuilder = panelBuilders[_activePanelIndex];

    return Row(
      children: [
        if (activePanelBuilder != null)
          SizedBox(width: _panelWidth, child: activePanelBuilder()),
        if (activePanelBuilder != null)
          MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: GestureDetector(
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _panelWidth += details.delta.dx;
                  if (_panelWidth < 250) _panelWidth = 250;
                  if (_panelWidth > 600) _panelWidth = 600;
                });
              },
              child: const VerticalDivider(width: 8, thickness: 10),
            ),
          ),
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
    return _SidePanelTemplate(
      title: 'File Options',
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
    );
  }

  Widget _buildEditPanel() {
    return _SidePanelTemplate(
      title: 'Editing Tools',
      child: ListView(
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
    );
  }

  Widget _buildLabelPanel() {
    final Map<String, dynamic> labelValuesMap =
        (_labelSettings?['labels']?['values'] as Map?)
            ?.cast<String, dynamic>() ??
        {};
    final String? requiredColumn = _labelSettings?['labels']?['column_name'];
    final bool isLabelColumnAvailable =
        requiredColumn != null &&
        _filteredCsvHeaders != null &&
        _filteredCsvHeaders!.contains(requiredColumn);
    final bool canUseSettingsSource =
        _labelSettings != null && isLabelColumnAvailable;
    final bool labelColumnIsNumeric = _isLabelColumnNumeric();

    return _SidePanelTemplate(
      title: 'Label Settings',
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          SwitchListTile(
            title: const Text('Show Labels on Chart'),
            value: _showLabels,
            onChanged: (value) {
              setState(() {
                _showLabels = value;
                if (value == true &&
                    _labelColumnIndex == null &&
                    _filteredCsvHeaders != null) {
                  int defaultIndex = _filteredCsvHeaders!.indexWhere(
                    (h) => h.toLowerCase().contains('label'),
                  );
                  if (defaultIndex != -1) {
                    _updateLabelColumn(defaultIndex);
                  }
                }
              });
              _saveShowLabelsPreference();
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings_suggest),
            title: const Text('Load Settings File'),
            subtitle: const Text('Import labels from a .json file'),
            onTap: _loadLabelSettings,
          ),
          const Divider(height: 24),
          const Text(
            'Label Source',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SegmentedButton<LabelSource>(
            segments: const [
              ButtonSegment(
                value: LabelSource.fromCsv,
                label: Text('From Data'),
              ),
              ButtonSegment(
                value: LabelSource.fromSettings,
                label: Text('From Settings'),
              ),
            ],
            selected: {_activeLabelSource},
            onSelectionChanged: (newSelection) {
              final selectedSource = newSelection.first;
              if (selectedSource == LabelSource.fromSettings &&
                  !canUseSettingsSource) {
                _showSnackbar(
                  'Cannot use settings: Required column "$requiredColumn" is not selected.',
                  isError: true,
                );
                return;
              }
              setState(() {
                _activeLabelSource = selectedSource;
                if (_activeLabelSource == LabelSource.fromSettings) {
                  final auto = _autoPickActiveLabelFromSettings();
                  if (auto != null) {
                    _selectedLabelValue = auto;
                  } else if (_selectedActiveLabels.isNotEmpty &&
                      _labelSettings != null) {
                    _selectedLabelValue = _isLabelColumnNumeric()
                        ? labelValuesMap[_selectedActiveLabels.first]
                        : _selectedActiveLabels.first;
                  } else {
                    _selectedLabelValue = null;
                  }
                } else {
                  _updateLabelColumn(_labelColumnIndex);
                }
                _chartData = _prepareChartData(_filteredCsvData!);
                _originalChartData = _prepareChartData(_filteredCsvData!);
              });
            },
          ),
          const SizedBox(height: 16),
          const Text(
            'Label Column',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          (_activeLabelSource == LabelSource.fromSettings &&
                  _labelSettings != null)
              ? ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.lock_outline),
                  title: Text(requiredColumn ?? "Error"),
                  subtitle: const Text('Defined by settings file'),
                )
              : DropdownButton<int>(
                  isExpanded: true,
                  value: _labelColumnIndex,
                  hint: const Text('Choose column for labels'),
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
          const SizedBox(height: 16),
          const Text(
            'Active Label Value (for Editing)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          DropdownButton<dynamic>(
            isExpanded: true,
            value: _selectedLabelValue,
            hint: const Text('Select value to apply'),
            items:
                (_activeLabelSource == LabelSource.fromSettings &&
                    _labelSettings != null)
                ? _selectedActiveLabels.map((labelName) {
                    final mapped = labelValuesMap[labelName];
                    return DropdownMenuItem<dynamic>(
                      value: labelColumnIsNumeric ? mapped : labelName,
                      child: Text(labelName),
                    );
                  }).toList()
                : _uniqueValuesInLabelColumn.map((value) {
                    return DropdownMenuItem<dynamic>(
                      value: value,
                      child: Text(value.toString()),
                    );
                  }).toList(),
            onChanged: (newValue) => setState(() {
              _selectedLabelValue = newValue;
              _treeProbabilities = null;
              _chartData = _prepareChartData(_filteredCsvData!);
              _originalChartData = _prepareChartData(_filteredCsvData!);
            }),
          ),
          if (_activeLabelSource == LabelSource.fromSettings &&
              _labelSettings != null) ...[
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Selectable Labels',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Row(
                  children: [
                    TextButton(
                      child: const Text('All'),
                      onPressed: () {
                        setState(() {
                          _selectedActiveLabels.addAll(labelValuesMap.keys);
                          // Re-pick the best label
                          final auto = _autoPickActiveLabelFromSettings();
                          _selectedLabelValue =
                              auto ??
                              (_selectedActiveLabels.isNotEmpty
                                  ? (_isLabelColumnNumeric()
                                        ? labelValuesMap[_selectedActiveLabels
                                              .first]
                                        : _selectedActiveLabels.first)
                                  : null);
                          if (_filteredCsvData != null) {
                            _chartData = _prepareChartData(_filteredCsvData!);
                            _originalChartData = _prepareChartData(
                              _filteredCsvData!,
                            );
                          }
                        });
                        _saveActiveLabelSelection();
                      },
                    ),
                    TextButton(
                      child: const Text('None'),
                      onPressed: () {
                        setState(() {
                          _selectedActiveLabels.clear();
                          _selectedLabelValue = null;
                          if (_filteredCsvData != null) {
                            _chartData = _prepareChartData(_filteredCsvData!);
                            _originalChartData = _prepareChartData(
                              _filteredCsvData!,
                            );
                          }
                        });
                        _saveActiveLabelSelection();
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView(
                shrinkWrap: true,
                children: labelValuesMap.keys.map((String labelName) {
                  return CheckboxListTile(
                    title: Text(labelName),
                    value: _selectedActiveLabels.contains(labelName),
                    onChanged: (bool? value) {
                      setState(() {
                        if (value == true) {
                          _selectedActiveLabels.add(labelName);
                        } else {
                          _selectedActiveLabels.remove(labelName);
                        }
                        // Re-pick the best label
                        final auto = _autoPickActiveLabelFromSettings();
                        _selectedLabelValue =
                            auto ??
                            (_selectedActiveLabels.isNotEmpty
                                ? (_isLabelColumnNumeric()
                                      ? labelValuesMap[_selectedActiveLabels
                                            .first]
                                      : _selectedActiveLabels.first)
                                : null);

                        if (_filteredCsvData != null) {
                          _chartData = _prepareChartData(_filteredCsvData!);
                          _originalChartData = _prepareChartData(
                            _filteredCsvData!,
                          );
                        }
                      });
                      _saveActiveLabelSelection();
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNormalizePanel() {
    return _SidePanelTemplate(
      title: 'Normalize Data',
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          SwitchListTile(
            title: const Text('Enable Normalization'),
            value: _isNormalizationEnabled,
            onChanged: (value) =>
                setState(() => _isNormalizationEnabled = value),
          ),
          const SizedBox(height: 16),
          if (_isNormalizationEnabled)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Target Percentile',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                SegmentedButton<double>(
                  segments: const [
                    ButtonSegment(value: 1.0, label: Text('P100')),
                    ButtonSegment(value: 0.95, label: Text('P95')),
                    ButtonSegment(value: 0.75, label: Text('P75')),
                  ],
                  selected: {_normalizationPercentile},
                  onSelectionChanged: (newSelection) => setState(
                    () => _normalizationPercentile = newSelection.first,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildZoomPanel() {
    return _SidePanelTemplate(
      title: 'Zoom Controls',
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
    );
  }

  Widget _buildPlotSettingsPanel() {
    return _SidePanelTemplate(
      title: 'Plot Settings',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Chart Type', style: Theme.of(context).textTheme.titleMedium),
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
            onChanged: (value) => setState(() => _lineWidth = value),
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
    );
  }

  Widget _buildMlPanel() {
    String formatMetadataValue(dynamic value) {
      if (value is Map)
        return const JsonEncoder.withIndent('  ').convert(value);
      return value.toString();
    }

    final bool canAutoLabel =
        _labelColumnIndex != null &&
        _selectedLabelValue != null &&
        _treeProbabilities != null;

    return _SidePanelTemplate(
      title: 'Tree Model Tools',
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
          if (_treeModel != null) ...[
            const Divider(height: 24),
            ExpansionTile(
              title: const Text('Model Metadata'),
              initiallyExpanded: true,
              children: _treeModel!.meta.entries.map((entry) {
                return ListTile(
                  title: Text(
                    entry.key,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  subtitle: SelectableText(formatMetadataValue(entry.value)),
                );
              }).toList(),
            ),
            const Divider(height: 24),
            Text("Controls", style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Show Probabilities'),
              value: _showProbabilities,
              onChanged: _treeProbabilities == null
                  ? null
                  : (value) => setState(() => _showProbabilities = value),
            ),
            if (_showProbabilities && _treeProbabilities != null) ...[
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Line'),
                    icon: Icon(Icons.show_chart),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Bar'),
                    icon: Icon(Icons.bar_chart),
                  ),
                ],
                selected: {_probabilityChartTypeIsBar},
                onSelectionChanged: (newSelection) => setState(
                  () => _probabilityChartTypeIsBar = newSelection.first,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Opacity: ${(_probabilityOpacity * 100).toStringAsFixed(0)}%',
              ),
              Slider(
                value: _probabilityOpacity,
                min: 0.1,
                max: 1.0,
                onChanged: (value) =>
                    setState(() => _probabilityOpacity = value),
              ),
            ],
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
                  : (value) => setState(() {
                      _autoLabelAddThreshold = value;
                      if (_autoLabelRemoveThreshold > value)
                        _autoLabelRemoveThreshold = value;
                    }),
            ),
            Text(
              'Remove labels if < ${(_autoLabelRemoveThreshold * 100).toStringAsFixed(0)}%',
            ),
            Slider(
              value: _autoLabelRemoveThreshold,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              label: '${(_autoLabelRemoveThreshold * 100).toStringAsFixed(0)}%',
              onChanged: !canAutoLabel
                  ? null
                  : (value) => setState(() {
                      _autoLabelRemoveThreshold = value;
                      if (_autoLabelAddThreshold < value)
                        _autoLabelAddThreshold = value;
                    }),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Apply Auto-Labels'),
              onPressed: canAutoLabel ? _applyAutoLabels : null,
            ),
          ],
        ],
      ),
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
                icon: const Icon(Icons.refresh),
                onPressed: _loadCsvFilesInFolder,
                tooltip: 'Reload Folder',
              ),
              IconButton(
                icon: const Icon(Icons.folder_open),
                onPressed: _pickProjectFolder,
                tooltip: 'Change Project Folder',
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: TextField(
            controller: _projectFilterController,
            decoration: const InputDecoration(
              hintText: 'Filter files...',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _filteredCsvFilesInProject.isEmpty
              ? const Center(child: Text('No .csv files found in this folder.'))
              : ListView.builder(
                  itemCount: _filteredCsvFilesInProject.length,
                  itemBuilder: (context, index) {
                    final file = _filteredCsvFilesInProject[index];
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

// === REFACTORED WIDGET ===
// This reusable widget reduces boilerplate in all the `_build...Panel` methods.
class _SidePanelTemplate extends StatelessWidget {
  final String title;
  final Widget child;

  const _SidePanelTemplate({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        const Divider(height: 1),
        Expanded(child: child),
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
