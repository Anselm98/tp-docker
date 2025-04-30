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
    <title>Company01 - Database Connection</title>
    <style>
        body { 
            font-family: "Segoe UI", Arial, sans-serif; 
            margin: 0;
            padding: 0;
            background-color: #f8f9fa;
            color: #333;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
        }
        header {
            background-color: #2c3e50;
            color: white;
            padding: 20px;
            text-align: center;
            margin-bottom: 30px;
        }
        h1 {
            margin: 0;
        }
        .form-container {
            background-color: white;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            padding: 25px;
            margin-bottom: 20px;
        }
        .form-group { 
            margin-bottom: 15px; 
        }
        label { 
            display: inline-block; 
            width: 100px; 
            font-weight: bold;
        }
        input[type="text"], input[type="password"] { 
            padding: 8px; 
            width: 250px;
            border: 1px solid #ddd;
            border-radius: 4px;
        }
        input[type="submit"] {
            background-color: #3498db;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 4px;
            cursor: pointer;
            font-size: 16px;
            transition: background-color 0.3s;
        }
        input[type="submit"]:hover {
            background-color: #2980b9;
        }
        .result { 
            margin-top: 20px; 
            padding: 15px; 
            border-radius: 8px; 
            box-shadow: 0 2px 5px rgba(0,0,0,0.1);
        }
        .success { 
            background-color: #d4edda; 
            border: 1px solid #c3e6cb;
            color: #155724;
        }
        .error { 
            background-color: #f8d7da; 
            border: 1px solid #f5c6cb;
            color: #721c24;
        }
        footer {
            text-align: center;
            padding: 15px;
            font-size: 14px;
            color: #6c757d;
            margin-top: 30px;
        }
    </style>
</head>
<body>
    <header>
        <h1>Company01 - Database Connection Test</h1>
    </header>
    <div class="container">
        <div class="form-container">
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
            </form>
        </div>';

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

echo '
        <footer>
            &copy; ' . date("Y") . ' Company01. All rights reserved.
        </footer>
    </div>
</body>
</html>';
?> 