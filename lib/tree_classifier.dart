import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:math';

/// Represents a single node in a decision tree.
/// A node is either a decision point (internal node) based on a feature and threshold,
/// or a terminal point (leaf) containing class predictions.
class TreeNode {
  /// The index of the feature to split on. If -1, this node is a leaf.
  final int feature;

  /// The threshold value for the feature split.
  final double threshold;

  /// The index of the left child node (for feature values <= threshold).
  final int left;

  /// The index of the right child node (for feature values > threshold).
  final int right;

  /// For leaf nodes, this contains the class distribution (e.g., counts or probabilities).
  final List<double> value;

  TreeNode({
    required this.feature,
    required this.threshold,
    required this.left,
    required this.right,
    required this.value,
  });

  /// Returns true if this node is a leaf node (i.e., makes a final prediction).
  bool get isLeaf => feature == -1;

  factory TreeNode.fromJson(Map<String, dynamic> json) => TreeNode(
    feature: json['feature'] as int,
    threshold: (json['threshold'] as num).toDouble(),
    left: json['left'] as int,
    right: json['right'] as int,
    value: (json['value'] as List).map((v) => (v as num).toDouble()).toList(),
  );
}

/// Represents a single decision tree composed of multiple [TreeNode]s.
class Tree {
  /// The index of the root node in the `nodes` list.
  final int root;

  /// A flat list of all nodes that make up the tree.
  final List<TreeNode> nodes;

  Tree({required this.root, required this.nodes});

  factory Tree.fromJson(Map<String, dynamic> json) => Tree(
    root: (json['root'] ?? 0) as int,
    nodes: (json['nodes'] as List).map((e) => TreeNode.fromJson(e)).toList(),
  );

  /// Predicts the class probabilities for a given feature vector.
  /// The input `featuresSel` must be in the "selected" feature space (pre-sliced and pre-processed).
  List<double> predictProbaSel(List<double> featuresSel) {
    int i = root;
    while (true) {
      final n = nodes[i];
      if (n.isLeaf) {
        // Normalize the leaf's value counts to get probabilities.
        double sumOfValues = n.value.fold(0.0, (prev, curr) => prev + curr);
        if (sumOfValues <= 0.0) {
          // If sum is zero (e.g., an empty leaf), return a uniform distribution.
          return List<double>.filled(n.value.length, 1.0 / n.value.length);
        }
        return n.value.map((c) => c / sumOfValues).toList();
      }
      // Traverse to the next node based on the feature and threshold.
      i = (featuresSel[n.feature] <= n.threshold) ? n.left : n.right;
    }
  }
}

/// Represents an ensemble of decision trees (a "forest") and handles
/// preprocessing, prediction, and metadata storage.
///
/// Expected JSON structure:
/// {
///   "meta": { "author": "...", "description": "..." },
///   "trees": [ { "root": 0, "nodes": [ ... ] } ],
///   "class_labels": [0, 1],
///   "feature_map": { "names_selected": ["feature1", "feature2"] },
///   "preprocessing": { "use_log_transform": false, "standardization": null },
///   "decision": { "positive_class_id": 1, "threshold": 0.5 }
/// }
class TreeEnsembleClassifier {
  /// A list of all the trees in the ensemble.
  final List<Tree> trees;

  /// **NEW**: The file path from which this model was loaded. Useful for UI state.
  final String? sourcePath;

  /// **NEW**: Arbitrary metadata from the JSON file for display in the UI.
  final Map<String, dynamic> meta;

  // feature_map
  final List<int>? usedIndices; // indices into ORIGINAL vector
  final List<String>? namesSelected; // optional (preferred for UI)
  final List<String>? namesAll; // optional

  // labels / decision
  final List<int> classLabels; // e.g., [0, 1]
  final int? positiveClassId;
  final double? threshold;

  // preprocessing
  final bool useLogTransform;
  final bool useStandardization;
  final List<double>? meanSel; // SELECTED space stats
  final List<double>? scaleSel;

  TreeEnsembleClassifier({
    required this.trees,
    required this.meta,
    this.sourcePath,
    required this.usedIndices,
    required this.namesSelected,
    required this.namesAll,
    required this.classLabels,
    required this.positiveClassId,
    required this.threshold,
    required this.useLogTransform,
    required this.useStandardization,
    required this.meanSel,
    required this.scaleSel,
  });

  /// The list of feature names the model was trained on.
  /// This is used by the main app to validate against the loaded CSV headers.
  List<String> get featureNames =>
      namesSelected ?? namesAll ?? const <String>[];

  /// Parses a JSON map into a [TreeEnsembleClassifier] instance.
  factory TreeEnsembleClassifier.fromJson(
    Map<String, dynamic> j, {
    String? sourcePath,
  }) {
    final prep = j['preprocessing'] as Map<String, dynamic>;
    final std = prep['standardization']; // {mean, scale, space} OR null
    final fmap = j['feature_map'] as Map<String, dynamic>;
    final dec = j['decision'] as Map<String, dynamic>;

    final usedIdx = (fmap['used_indices'] as List?)
        ?.map((e) => e as int)
        .toList();
    final namesSel = (fmap['names_selected'] as List?)?.cast<String>();
    final namesAll = (fmap['names_all'] as List?)?.cast<String>();

    List<double>? meanSel, scaleSel;
    if (std != null) {
      meanSel = (std['mean'] as List?)
          ?.map((e) => (e as num).toDouble())
          .toList();
      scaleSel = (std['scale'] as List?)
          ?.map((e) => (e as num).toDouble())
          .toList();
    }

    return TreeEnsembleClassifier(
      trees: (j['trees'] as List).map((e) => Tree.fromJson(e)).toList(),
      sourcePath: sourcePath, // NEW: Store the source path
      meta:
          (j['meta'] as Map<String, dynamic>?) ??
          const {}, // NEW: Store meta, with a default
      usedIndices: usedIdx,
      namesSelected: namesSel,
      namesAll: namesAll,
      classLabels: (j['class_labels'] as List).map((e) => e as int).toList(),
      positiveClassId: dec['positive_class_id'] as int?,
      threshold: dec['threshold'] == null
          ? null
          : (dec['threshold'] as num).toDouble(),
      useLogTransform: (prep['use_log_transform'] as bool? ?? false),
      useStandardization: (prep['use_standardization'] as bool? ?? false),
      meanSel: meanSel,
      scaleSel: scaleSel,
    );
  }

  /// Creates a [TreeEnsembleClassifier] from a JSON file.
  static Future<TreeEnsembleClassifier?> fromFile(File file) async {
    try {
      final String content = await file.readAsString();
      // NEW: Pass the file path to the fromJson factory
      return TreeEnsembleClassifier.fromJson(
        jsonDecode(content),
        sourcePath: file.path,
      );
    } catch (e) {
      debugPrint("Error loading or parsing tree model: $e");
      return null;
    }
  }

  /// Preprocesses an input feature vector.
  /// It automatically handles log transformation, feature slicing, and standardization.
  List<double> _preprocessAuto(List<double> xIn) {
    // 1) Log transform
    List<double> x = List<double>.from(xIn);
    if (useLogTransform) {
      const eps = 1e-9;
      for (int i = 0; i < x.length; i++) x[i] = log(x[i].abs() + eps);
    }

    // 2) Slice to selected features if a full vector was provided.
    List<double> xSel;
    if (usedIndices == null || usedIndices!.isEmpty) {
      xSel = x;
    } else {
      xSel = List<double>.filled(usedIndices!.length, 0.0, growable: true);
      for (int i = 0; i < usedIndices!.length; i++) {
        xSel[i] = x[usedIndices![i]];
      }
    }

    // 3) Standardize in the selected feature space.
    if (useStandardization && meanSel != null && scaleSel != null) {
      if (xSel.length != meanSel!.length || xSel.length != scaleSel!.length) {
        throw StateError(
          "Standardization mismatch: xSel=${xSel.length}, mean=${meanSel!.length}, scale=${scaleSel!.length}",
        );
      }
      for (int i = 0; i < xSel.length; i++) {
        final s = (scaleSel![i].abs() < 1e-9)
            ? 1.0
            : scaleSel![i]; // Avoid division by zero
        xSel[i] = (xSel[i] - meanSel![i]) / s;
      }
    }

    return xSel;
  }

  /// Predicts the probability distribution over all classes.
  /// Averages the predictions from all trees in the ensemble.
  List<double> predictProba(List<double> features) {
    if (trees.isEmpty) return const <double>[];
    final xSel = _preprocessAuto(features);

    final probs = List<double>.filled(classLabels.length, 0.0);
    for (final t in trees) {
      final p = t.predictProbaSel(xSel);
      for (int k = 0; k < probs.length; k++) probs[k] += p[k];
    }
    for (int k = 0; k < probs.length; k++) probs[k] /= trees.length;
    return probs;
  }

  /// Predicts the probability of the "positive" class.
  /// This is the primary prediction method used by the main application's chart.
  double predict(List<double> features) {
    if (positiveClassId == null) {
      // Default to the max probability if no positive class is defined.
      final p = predictProba(features);
      return p.isEmpty ? 0.0 : p.reduce(max);
    }
    final p = predictProba(features);
    final idx = classLabels.indexOf(positiveClassId!);
    if (idx < 0) return 0.0;
    return p[idx];
  }

  /// Predicts the final class label by finding the class with the highest probability.
  int predictClass(List<double> features) {
    final p = predictProba(features);
    if (p.isEmpty) return -1; // Or some default/error value

    int argmax = 0;
    double best = -1.0;
    for (int k = 0; k < p.length; k++) {
      if (p[k] > best) {
        best = p[k];
        argmax = k;
      }
    }
    return classLabels[argmax];
  }

  /// Returns a binary decision (true/false) based on the positive class probability
  /// and the model's decision threshold.
  bool predictBinaryPass(List<double> features) {
    if (positiveClassId == null || threshold == null) {
      throw StateError(
        "positive_class_id and threshold are required for binary decision.",
      );
    }
    final p = predictProba(features);
    final idx = classLabels.indexOf(positiveClassId!);
    if (idx < 0)
      throw StateError("positive_class_id not found in class_labels.");
    return p[idx] >= threshold!;
  }
}
