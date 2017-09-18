#include <iostream>
#include <atomic>
#include <thread>
#include <mutex>
#include <condition_variable>


using namespace std;


class EasySemaphore {
public:
    EasySemaphore(int value=0): count{value} {}
    
    void wait(){
        unique_lock<std::mutex> lock{mmutex};
        if (--count<0) {
            condition.wait(lock, [&]()->bool{ return count >= 0;});
        }
    }
    void signal(){
        
        unique_lock<std::mutex> lock(mmutex);
        if(++count<=0) {
            condition.notify_one();
        }
    }
    
private:
    int count;
    std::mutex mmutex;
    std::condition_variable condition;
};


int x=0;
int y=0;
int r1=0;
int r2=0;

void thread1(){
    x = 1;
    r1 = y;
}

void thread2(){
    y = 1;
    r2 = x;
}

EasySemaphore sem1, sem2, sem;


int main(){
    std::thread thread_1([](){
        while(1){
            sem1.wait();
            thread1();
            sem.signal();
        }
    });
    std::thread thread_2([](){
        while(1){
            sem2.wait();
            thread2();
            sem.signal();
        }
    });
    
    
    int count = 0;
    int reorder = 0;
    while(1){
        count ++;
        x=0;y=0;r1=0;r2=0;
        sem1.signal();
        sem2.signal();
        
        sem.wait();
        sem.wait();
        if(r1==0 && r2==0){
            reorder ++;
        }
        cout << "reorder count(" << reorder << "), total count(" << count << ")" << endl;
    }

    return 0;
}



