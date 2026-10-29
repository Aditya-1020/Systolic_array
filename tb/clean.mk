TOPLEVEL ?= pe

.PHONY: clean

clean:
	rm -rf sim_build_$(TOPLEVEL)
	rm -rf __pycache__
	rm -f results.xml
