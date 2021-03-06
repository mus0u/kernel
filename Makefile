ARCH?=x86_64

QEMU=qemu-system-$(ARCH)
QEMUFLAGS=-serial mon:stdio -d guest_errors

ifeq ($(ARCH),arm)
	LD=$(ARCH)-none-eabi-ld
	QEMUFLAGS+=-cpu arm1176 -machine integratorcp
	QEMUFLAGS+=-nographic
else
	LD=ld
	QEMUFLAGS+=-enable-kvm -cpu host -machine q35 -smp 4
	#,int,pcall
	#-nographic
	#-device intel-iommu

	UNAME := $(shell uname)
	ifeq ($(UNAME),Darwin)
		LD=$(ARCH)-elf-ld
		QEMUFLAGS=
	endif
endif

all: build/kernel.bin

list: build/kernel.list

run: bochs

bochs: build/harddrive.bin
	bochs -f bochs.$(ARCH)

FORCE:

build/libcore.rlib: rust/src/libcore/lib.rs
	mkdir -p build
	./rustc.sh --target $(ARCH)-unknown-none.json -C soft-float -o $@ $<

build/liballoc.rlib: rust/src/liballoc/lib.rs build/libcore.rlib
	mkdir -p build
	./rustc.sh --target $(ARCH)-unknown-none.json -C soft-float -o $@ $<

build/librustc_unicode.rlib: rust/src/librustc_unicode/lib.rs build/libcore.rlib
	mkdir -p build
	./rustc.sh --target $(ARCH)-unknown-none.json -C soft-float -o $@ $<

build/libcollections.rlib: rust/src/libcollections/lib.rs build/libcore.rlib build/liballoc.rlib build/librustc_unicode.rlib
	mkdir -p build
	./rustc.sh --target $(ARCH)-unknown-none.json -C soft-float -o $@ $<

build/libkernel.a: build/libcore.rlib build/liballoc.rlib build/libcollections.rlib FORCE
	mkdir -p build
	RUSTC="./rustc.sh" cargo rustc --target $(ARCH)-unknown-none.json -- -C soft-float -o $@

build/kernel.bin: build/libkernel.a
	$(LD) --gc-sections -z max-page-size=0x1000 -T arch/$(ARCH)/src/linker.ld -o $@ $<

ifeq ($(ARCH),arm)
build/kernel.list: build/kernel.bin
	$(ARCH)-none-eabi-objdump -C -D $< > $@

qemu: build/kernel.bin
	$(QEMU) $(QEMUFLAGS) -kernel $<
else
build/kernel.list: build/kernel.bin
	objdump -C -M intel -D $< > $@

build/harddrive.bin: build/kernel.bin
	nasm -f bin -o $@ -D ARCH_$(ARCH) -ibootloader/$(ARCH)/ -ibuild/ bootloader/$(ARCH)/harddrive.asm

qemu: build/harddrive.bin
	$(QEMU) $(QEMUFLAGS) -drive file=$<,format=raw,index=0,media=disk
endif

clean:
	rm -rf build/* target/*
