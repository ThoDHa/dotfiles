CURRENT_DIR := $(shell basename $$PWD)
CONTAINER := base_dev
run:
	docker run -it --rm  -v .:/root/$(CURRENT_DIR) -w /root/$(CURRENT_DIR) $(CONTAINER):latest
build:
	docker build -t $(CONTAINER) .
