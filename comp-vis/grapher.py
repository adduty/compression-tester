import pandas as pd
from matplotlib import pyplot as plt
from matplotlib.widgets import CheckButtons

master = pd.read_csv('../data/master.csv')

zip = master[master.binary == 'zip']

gzip = master[master.binary == 'gzip']

bzip2 = master[master.binary == 'bzip2']

# l0 = plt.plot(zip.compression_level, zip.compressed_size / 1024**2, label='zip')
# l1 = plt.plot(gzip.compression_level, gzip.compressed_size / 1024**2, label='gzip')
# l2 = plt.plot(bzip2.compression_level, bzip2.compressed_size / 1024**2, label='bzip2')
# plt.legend(['zip', 'gzip', 'bzip2'])
# plt.xlabel('compression level')
# plt.ylabel('file size (mb)')

fig, ax = plt.subplots()
l0, = ax.plot(zip.compression_level, zip.compressed_size, label='zip')
l1, = ax.plot(gzip.compression_level, gzip.compressed_size, label='gzip')
l2, = ax.plot(bzip2.compression_level, bzip2.compressed_size, label='bzip2')
# lines = []
# data = []
# for alg in master['binary'].unique():
#     if not alg.isdigit():
#         data = master[master.binary == alg]
#         line = ax.plot(data.compression_level, data.compressed_size, label=alg)
#         lines.append(line)

lines = [l0, l1, l2]

rax = plt.axes([0.05, 0.4, 0.1, 0.15])
labels = [str(line.get_label()) for line in lines]
visibility = [line.get_visible() for line in lines]
check = CheckButtons(rax, labels, visibility)


def func(label):
    index = labels.index(label)
    lines[index].set_visible(not lines[index].get_visible())
    plt.draw()


check.on_clicked(func)

plt.show()
