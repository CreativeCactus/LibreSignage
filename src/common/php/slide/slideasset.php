<?php

require_once($_SERVER['DOCUMENT_ROOT'].'/common/php/config.php');
require_once($_SERVER['DOCUMENT_ROOT'].'/common/php/exportable/exportable.php');

const ASSET_MIMES = [
	'image/png',
	'image/jpeg',
	'image/gif',
	'video/mp4',
	'video/webm',
	'video/ogg'
];

class SlideAsset extends Exportable {
	static $PRIVATE = [
		'mime',
		'filename',
		'uid',
		'intname',
		'fullpath'
	];
	static $PUBLIC = [
		'mime',
		'filename'
	];

	private $mime = NULL;
	private $filename = NULL;
	private $uid = NULL;
	private $intname = NULL;
	private $fullpath = NULL;

	public function __exportable_get(string $name) {
		return $this->{$name};
	}

	public function __exportable_set(string $name, $value) {
		$this->{$name} = $value;
	}

	public function new(array $file, string $asset_path) {
		assert(!empty($file));
		assert(!empty($asset_path));

		$mime = mime_content_type($file['tmp_name']);
		if (!in_array($mime, ASSET_MIMES, TRUE)) {
			throw new ArgException("Invalid asset MIME type.");
		}
		if (strlen($file['name']) > gtlim('SLIDE_ASSET_NAME_MAX_LEN')) {
			throw new ArgException("Asset filename too long.");
		}

		$this->filename = basename($file['name']);
		$this->mime = $mime;
		$this->uid = get_uid();

		$this->intname = $this->uid.'.'.explode('/', $this->mime)[1];
		$this->fullpath = $asset_path.'/'.$this->intname;

		if (!move_uploaded_file($file['tmp_name'], $this->fullpath)) {
			throw new IntException("Failed to store uploaded asset.");
		}
	}

	public function remove() {
		if (!empty($this->fullpath)) {
			unlink($this->fullpath);
		}
	}

	public function get_filename() {
		return $this->filename;
	}
}
