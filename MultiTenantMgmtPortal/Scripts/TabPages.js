﻿
function pageChange(source, page) {
    'use strict';

    $('.tabPage').hide();
    $('#' + page).show();
    $('.tabButtonActive').removeClass('tabButtonActive');
    $('#' + source).addClass('tabButtonActive');
    $('#hidTab').val(source);
    $('#hidTabPage').val(page);
}