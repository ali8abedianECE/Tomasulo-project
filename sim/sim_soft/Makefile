CXX      = g++
CXXFLAGS = -std=c++17 -Wall -Wextra -O2

SRCS = sim.cpp \
       instruction.cpp \
       instruction_queue.cpp \
       regfile.cpp \
       register_remapping_table.cpp \
       reorder_buffer.cpp \
       reservation_station.cpp \
       buffer_station.cpp \
       load_store_buffer.cpp \
       commit_unit.cpp \
       common_data_bus.cpp

OBJS = $(SRCS:.cpp=.o)
TARGET = tomasulo_sim

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^

%.o: %.cpp
	$(CXX) $(CXXFLAGS) -c -o $@ $<

clean:
	rm -f $(OBJS) $(TARGET)

.PHONY: all clean
