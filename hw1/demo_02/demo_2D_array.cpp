#include <iostream>
#include <cstdlib>

int main() {
    int N = 30000; // ~3.6 GB
    int* matrix = (int*)malloc(N * N * sizeof(int));
     if (matrix == nullptr) {
        std::cerr << "malloc failed" << std::endl;
        return 1;
    }

    for (long long i = 0; i < N * N; i++)
        matrix[i] = 1;

    long long sum = 0;
    for (int col = 0; col < N; col++)
        for (int row = 0; row < N; row++)
            sum += matrix[row * N + col];

    std::cout << "Not Optimized" << std::endl;
    std::cout << "Sum: " << sum << std::endl;

    std::free(matrix);
    return 0;
}
