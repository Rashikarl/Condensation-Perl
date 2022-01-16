sub new($class) {
	return bless {
		isMerged => 0,
		hashAndKey => undef,
		size => 0,
		count => 0,
		selected => 0,
		};
}

# In this implementation, we only keep track of the number of values of the list, but
# not of the corresponding items. This saves memory (~100 MiB for 1M items), but takes
# more time (0.5 s for 1M items) when saving. Since command line programs usually write
# the data tree only once, this is acceptable. Reading the tree anyway takes about 10
# times more time.
