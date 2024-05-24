package tempdir

import (
	"os"
	"path/filepath"
	"testing"
)

func TestWriteFiles(t *testing.T) {
	fsroot := t.TempDir()
	files := map[string]string{
		"foo.txt": "Hello, world!",
		"bar.txt": "Goodbye, world!",
	}

	WriteFiles(fsroot, files, t)

	for file, want := range files {
		path := filepath.Join(fsroot, file)

		got, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("os.ReadFile(%s): %v", path, err)
		}

		if string(got) != want {
			t.Errorf("os.ReadFile(%s) = %q; want %q", path, string(got), want)
		}
	}
}
