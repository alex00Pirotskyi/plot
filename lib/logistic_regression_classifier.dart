// lib/logistic_regression_classifier.dart

import 'dart:math';

class LogisticRegressionClassifier {
  final double learningRate;
  final int numIterations;

  List<double>? _weights;
  double _bias = 0.0;

  LogisticRegressionClassifier({
    this.learningRate = 0.1,
    this.numIterations = 500,
  });

  /// The sigmoid function, which squashes any value into the 0-1 range.
  /// This is what allows us to output a probability.
  double _sigmoid(double z) {
    return 1.0 / (1.0 + exp(-z));
  }

  /// Trains the model on the provided data (X) and labels (y).
  void train(List<List<double>> X, List<int> y) {
    final int numSamples = X.length;
    final int numFeatures = X.first.length;

    // 1. Initialize weights and bias to zero.
    _weights = List.filled(numFeatures, 0.0);
    _bias = 0.0;

    // 2. Gradient Descent: Iteratively adjust weights and bias to minimize error.
    for (int i = 0; i < numIterations; i++) {
      // Calculate the linear model prediction for all samples
      final List<double> predictions = X.map((sample) {
        double linearModel = 0.0;
        for (int j = 0; j < numFeatures; j++) {
          linearModel += _weights![j] * sample[j];
        }
        linearModel += _bias;
        return _sigmoid(linearModel);
      }).toList();

      // Calculate the error (difference between prediction and actual label)
      final List<double> errors = List.generate(
        numSamples,
        (k) => predictions[k] - y[k],
      );

      // Calculate the gradients (the direction to adjust weights/bias)
      final List<double> dW = List.filled(numFeatures, 0.0);
      double dB = 0.0;
      for (int k = 0; k < numSamples; k++) {
        for (int j = 0; j < numFeatures; j++) {
          dW[j] += X[k][j] * errors[k];
        }
        dB += errors[k];
      }

      // Average the gradients
      for (int j = 0; j < numFeatures; j++) {
        dW[j] /= numSamples;
      }
      dB /= numSamples;

      // 3. Update weights and bias in the opposite direction of the gradient.
      for (int j = 0; j < numFeatures; j++) {
        _weights![j] -= learningRate * dW[j];
      }
      _bias -= learningRate * dB;
    }
  }

  /// Predicts the probability for a single data sample.
  double predict(List<double> x) {
    if (_weights == null) {
      throw Exception("Model has not been trained yet.");
    }
    double linearModel = 0.0;
    for (int i = 0; i < _weights!.length; i++) {
      linearModel += _weights![i] * x[i];
    }
    linearModel += _bias;
    return _sigmoid(linearModel);
  }

  /// Predicts the probability for an entire dataset.
  List<double> predictForData(List<List<double>> X) {
    return X.map((sample) => predict(sample)).toList();
  }
}
