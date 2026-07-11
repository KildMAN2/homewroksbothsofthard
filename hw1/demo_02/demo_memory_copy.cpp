#include <iostream>

int main() {
    constexpr int N = 1000000000;
    int* src = new int[N];
    int* dst = new int[N];

    for (int i = 0; i < N; i++) {
        src[i] = i;
    }

    for (int i = 0; i < N; i++) {
        dst[i] = src[i];
    }

    long long sum = 0;
    for (int i = 0; i < N; i++) {
        sum += dst[i];
    }

    std::cout << "Not Optimized" << std::endl;
    std::cout << "Sum: " << sum << std::endl;

    delete[] src;
    delete[] dst;
    return 0;
}
