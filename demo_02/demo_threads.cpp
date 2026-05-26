#include <iostream>
#include <thread>
#include <vector>

void work(int id) {
    volatile long long sum = 0;
    for (int i = 0; i < 1000000; i++) {
        sum += i * id; 
    }
}

int main() {
    constexpr int N = 1000;
    std::vector<std::thread> threads;

    for (int i = 0; i < N; i++) {
        threads.emplace_back(work, i);
    }

    for (auto& t : threads) {
        t.join();
    }

    std::cout << "Not Optimized (new thread per task)" << std::endl;
    return 0;
}
