CXX      = g++
CXXFLAGS = -O2 -std=c++17 -g -Wall
TARGET     = hotel_traditional
EXT_TARGET = hotel_traditional_ext
SHARED     = hotel_system.o

$(TARGET): main.o $(SHARED)
	$(CXX) $(CXXFLAGS) -o $@ $^

$(EXT_TARGET): feature_extension.o $(SHARED)
	$(CXX) $(CXXFLAGS) -o $@ $^

main.o: main.cpp hotel_system.h models.h
	$(CXX) $(CXXFLAGS) -c $<

hotel_system.o: hotel_system.cpp hotel_system.h models.h
	$(CXX) $(CXXFLAGS) -c $<

feature_extension.o: feature_extension.cpp hotel_system.h models.h
	$(CXX) $(CXXFLAGS) -c $<

clean:
	rm -f *.o $(TARGET) $(EXT_TARGET)

.PHONY: clean