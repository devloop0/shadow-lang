SP=$(HOME)/spectre/opt_build/spectre
AS=/opt/arm_cross_compiler/bin/arm-linux-gnueabihf-as
LD=/opt/arm_cross_compiler/bin/arm-linux-gnueabihf-ld
GUEST_LD=ld

BUILD_DIR=build
ASM_DIR=$(BUILD_DIR)/asm
O_DIR=$(BUILD_DIR)/o
OUTPUT=$(BUILD_DIR)/shadow

SDW_DIR=/usr/include/libshadow
SDW_SRC_DIR=$(SDW_DIR)/src
SDW_MOD_DIR=$(SDW_DIR)/mod
SDW_LIB_DIR=$(SDW_DIR)/lib

FILES=$(shell find . -type f -wholename './*.sp' -not -path './rt/*' -printf '%P\n')
HEADERS=$(shell find . -type f -wholename './*.hsp' -not -path './rt/*' -printf '%P\n')
SDW_OBJECTS=$(patsubst %.sp, $(O_DIR)/%.o, $(subst /,!,$(FILES)))
SDW_ASSEMBLIES=$(patsubst %.sp, $(ASM_DIR)/%.s, $(subst /,!,$(FILES)))

all: setup $(OUTPUT)

setup:
	mkdir -p $(ASM_DIR) $(O_DIR)

.SECONDEXPANSION:
$(SDW_OBJECTS): $(O_DIR)/%.o: $(ASM_DIR)/%.s
	$(AS) -mfloat-abi=hard -mfpu=vfp -c $^ -o $@

.SECONDEXPANSION:
$(SDW_ASSEMBLIES): $(ASM_DIR)/%.s: ./$$(subst !,/,%.sp) $(HEADERS)
	$(SP) $<
	mv $(patsubst %.sp, %.s, $<) $@

.SECONDEXPANSION:
compile: setup $(SDW_OBJECTS)

$(OUTPUT): $(SDW_OBJECTS)
	$(LD) -o $(OUTPUT) $(SDW_OBJECTS) -L/usr/include/libspectre -l:libspectre.a

.SECONDEXPANSION:
link: $(SDW_OBJECTS)
	$(GUEST_LD) -o $(OUTPUT) $(SDW_OBJECTS) -L/usr/include/libspectre -l:libspectre.a

clean:
	rm -rf $(BUILD_DIR)

module_setup:
	mkdir -p $(SDW_DIR) $(SDW_MOD_DIR) $(SDW_SRC_DIR) $(SDW_LIB_DIR)
