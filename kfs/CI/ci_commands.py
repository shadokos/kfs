from ci_core import Tests, Test, Client

client = Client('localhost', 4444)

test_allocations = Tests(client, "Allocations")

test_allocations.add(Test("Physical memory allocator", "kfuzz 100000 32000",))
test_allocations.add(Test("Virtual memory allocator", "vfuzz 100000 64000"))

test_allocations.run()
