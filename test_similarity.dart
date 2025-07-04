import 'dart:math' as math;
import 'dart:convert';

void main() {
  print('Testing similarity calculation...');
  
  // Test 1: Generate a normalized random vector (simulate registration)
  final random = math.Random();
  final registeredVector = List<double>.generate(
    128, 
    (i) => random.nextDouble() * 2 - 1, // -1 to 1
  );
  
  // Normalize the registered vector
  double norm = math.sqrt(
    registeredVector.fold(0.0, (sum, val) => sum + val * val),
  );
  if (norm > 0) {
    for (int i = 0; i < registeredVector.length; i++) {
      registeredVector[i] = registeredVector[i] / norm;
    }
  }
  
  print('Registered vector (first 5 elements): ${registeredVector.take(5).toList()}');
  print('Registered vector norm: ${math.sqrt(registeredVector.fold(0.0, (sum, val) => sum + val * val))}');
  
  // Test 2: Generate a similar vector (simulate verification)
  final verifyVector = List<double>.from(
    registeredVector.map((val) {
      double noise = (random.nextDouble() - 0.5) * 0.1; // ±5% noise
      return val + noise;
    }),
  );
  
  // Normalize the verify vector
  norm = math.sqrt(
    verifyVector.fold(0.0, (sum, val) => sum + val * val),
  );
  if (norm > 0) {
    for (int i = 0; i < verifyVector.length; i++) {
      verifyVector[i] = verifyVector[i] / norm;
    }
  }
  
  print('Verify vector (first 5 elements): ${verifyVector.take(5).toList()}');
  print('Verify vector norm: ${math.sqrt(verifyVector.fold(0.0, (sum, val) => sum + val * val))}');
  
  // Test 3: Calculate cosine similarity
  final similarity = calculateSimilarity(registeredVector, verifyVector);
  print('Cosine similarity: ${similarity}');
  print('Similarity percentage: ${(similarity * 100).toStringAsFixed(1)}%');
  
  // Test 4: Test with completely different vectors
  final differentVector = List<double>.generate(
    128, 
    (i) => random.nextDouble() * 2 - 1,
  );
  
  // Normalize different vector
  norm = math.sqrt(
    differentVector.fold(0.0, (sum, val) => sum + val * val),
  );
  if (norm > 0) {
    for (int i = 0; i < differentVector.length; i++) {
      differentVector[i] = differentVector[i] / norm;
    }
  }
  
  final differentSimilarity = calculateSimilarity(registeredVector, differentVector);
  print('Similarity with different vector: ${(differentSimilarity * 100).toStringAsFixed(1)}%');
  
  // Test 5: Test with identical vectors
  final identicalSimilarity = calculateSimilarity(registeredVector, registeredVector);
  print('Similarity with identical vector: ${(identicalSimilarity * 100).toStringAsFixed(1)}%');
}

double calculateSimilarity(List<dynamic> vector1, List<dynamic> vector2) {
  if (vector1.length != vector2.length) return 0.0;

  double dotProduct = 0.0;
  double norm1 = 0.0;
  double norm2 = 0.0;

  for (int i = 0; i < vector1.length; i++) {
    double v1 = vector1[i].toDouble();
    double v2 = vector2[i].toDouble();
    dotProduct += v1 * v2;
    norm1 += v1 * v1;
    norm2 += v2 * v2;
  }

  if (norm1 == 0.0 || norm2 == 0.0) return 0.0;

  return dotProduct / (math.sqrt(norm1) * math.sqrt(norm2));
}
