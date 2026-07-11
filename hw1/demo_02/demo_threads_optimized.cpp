#include <iostream>
#include <thread>
#include <vector>
#include <queue>
#include <mutex>
#include <condition_variable>
#include <functional>

constexpr int N = 1000;
constexpr int NUM_THREADS = 8;

std::queue<std::function<void()>> tasks;
std::mutex tasks_mutex;
std::condition_variable tasks_cv;
bool done = false;

void worker() {
    while (true) {
        std::function<void()> task;
        {
            std::unique_lock<std::mutex> lock(tasks_mutex);
            tasks_cv.wait(lock, [] { return !tasks.empty() || done; });

            if (done && tasks.empty()) break;

            task = std::move(tasks.front());
            tasks.pop();
        }
        task();
    }
}

void work(int id) {
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
}

int main() {
    std::vector<std::thread> pool;
    for (int i = 0; i < NUM_THREADS; ++i) {
        pool.emplace_back(worker);
    }

    for (int i = 0; i < N; ++i) {
        {
            std::lock_guard<std::mutex> lock(tasks_mutex);
            tasks.push([i]() { work(i); });
        }
        tasks_cv.notify_one();
    }

    {
        std::lock_guard<std::mutex> lock(tasks_mutex);
        done = true;
    }
    tasks_cv.notify_all();

    for (auto& thread : pool) {
        thread.join();
    }

    std::cout << "Optimized (thread pool)\n";
    return 0;
}
