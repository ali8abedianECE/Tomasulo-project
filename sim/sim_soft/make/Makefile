CXX      = g++
CXXFLAGS = -std=c++17 -Wall -Wextra -O2 -I../include

SRCDIR = ..
SRCS = \
    $(SRCDIR)/sim.cpp \
    $(SRCDIR)/instruction.cpp \
    $(SRCDIR)/instruction_queue.cpp \
    $(SRCDIR)/regfile.cpp \
    $(SRCDIR)/register_remapping_table.cpp \
    $(SRCDIR)/reorder_buffer.cpp \
    $(SRCDIR)/reservation_station.cpp \
    $(SRCDIR)/buffer_station.cpp \
    $(SRCDIR)/load_store_buffer.cpp \
    $(SRCDIR)/commit_unit.cpp \
    $(SRCDIR)/common_data_bus.cpp

OBJS   = $(notdir $(SRCS:.cpp=.o))
TARGET = tomasulo_sim

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^

%.o: $(SRCDIR)/%.cpp
	$(CXX) $(CXXFLAGS) -c -o $@ $<

clean:
	rm -f $(OBJS) $(TARGET)

.PHONY: all clean
