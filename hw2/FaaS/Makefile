CXX      = g++
CXXFLAGS = -O2 -std=c++17 -g -Wall
TARGET     = hotel_faas
EXT_TARGET = hotel_faas_ext

SHARED = storage.o faas_functions.o

$(TARGET): main.o $(SHARED)
	$(CXX) $(CXXFLAGS) -o $@ $^

$(EXT_TARGET): feature_extension.o $(SHARED)
	$(CXX) $(CXXFLAGS) -o $@ $^

%.o: %.cpp faas_functions.h storage.h models.h
	$(CXX) $(CXXFLAGS) -c $<

clean:
	rm -f *.o $(TARGET) $(EXT_TARGET)

.PHONY: clean