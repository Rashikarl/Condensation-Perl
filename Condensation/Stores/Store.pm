# General
# sub id($o)				# () => String

# Object store functions
# sub get($o, $hash, $keyPair)				# Hash, KeyPair? => Object?, String?
# sub put($o, $hash, $object, $keyPair)		# Hash, Object, KeyPair? => String?
# sub book($o, $hash, $keyPair)				# Hash, KeyPair? => 1?, String?

# Account store functions
# sub list($o, $accountHash, $boxLabel, $timeout, $keyPair)		# Hash, String, Duration, KeyPair? => @$Hash, String?
# sub add($o, $accountHash, $boxLabel, $hash, $keyPair)			# Hash, String, Hash, KeyPair? => String?
# sub remove($o, $accountHash, $boxLabel, $hash, $keyPair)		# Hash, String, Hash, KeyPair? => String?
# sub modify($o, $storeModifications, $keyPair)					# StoreModifications, KeyPair? => String?
