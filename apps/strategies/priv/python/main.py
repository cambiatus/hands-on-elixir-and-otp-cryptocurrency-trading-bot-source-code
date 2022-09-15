from PIL import Image


def sample(color):
    img = Image.new('RGB', (60, 30), color=color)
    img.show()
