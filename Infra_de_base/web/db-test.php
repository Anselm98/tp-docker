<?php
// Default values
$host = isset($_POST['host']) ? $_POST['host'] : 'db';
$user = isset($_POST['user']) ? $_POST['user'] : 'root';
$pass = isset($_POST['pass']) ? $_POST['pass'] : 'michel';
$dbname = isset($_POST['dbname']) ? $_POST['dbname'] : 'mysql';

// Display the form
echo '<!DOCTYPE html>
<html>
<head>
    <title>Database Connection Test</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .form-group { margin-bottom: 10px; }
        label { display: inline-block; width: 100px; }
        input { padding: 5px; }
        .result { margin-top: 20px; padding: 10px; border: 1px solid #ccc; }
        .success { background-color: #dff0d8; }
        .error { background-color: #f2dede; }
    </style>
</head>
<body>
    <h1>Database Connection Test</h1>
    <form method="post">
        <div class="form-group">
            <label for="host">Host:</label>
            <input type="text" name="host" value="' . htmlspecialchars($host) . '" required>
        </div>
        <div class="form-group">
            <label for="user">Username:</label>
            <input type="text" name="user" value="' . htmlspecialchars($user) . '" required>
        </div>
        <div class="form-group">
            <label for="pass">Password:</label>
            <input type="password" name="pass" value="' . htmlspecialchars($pass) . '" required>
        </div>
        <div class="form-group">
            <label for="dbname">Database:</label>
            <input type="text" name="dbname" value="' . htmlspecialchars($dbname) . '" required>
        </div>
        <div class="form-group">
            <input type="submit" value="Test Connection">
        </div>
    </form>';

// If form is submitted, test the connection
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    try {
        $conn = new mysqli($host, $user, $pass, $dbname);
        
        if ($conn->connect_error) {
            throw new Exception("Connection failed: " . $conn->connect_error);
        }
        
        echo '<div class="result success">';
        echo '<h2>Connection Successful!</h2>';
        echo '<p>Server version: ' . $conn->server_info . '</p>';
        
        // Test query
        $result = $conn->query("SHOW DATABASES");
        echo '<h3>Available Databases:</h3>';
        echo '<ul>';
        while ($row = $result->fetch_assoc()) {
            echo '<li>' . htmlspecialchars($row['Database']) . '</li>';
        }
        echo '</ul>';
        
        $conn->close();
        echo '</div>';
    } catch (Exception $e) {
        echo '<div class="result error">';
        echo '<h2>Connection Failed</h2>';
        echo '<p>' . htmlspecialchars($e->getMessage()) . '</p>';
        echo '</div>';
    }
}

echo '</body></html>';
?> 